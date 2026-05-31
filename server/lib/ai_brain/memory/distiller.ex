defmodule AIBrain.Memory.Distiller do
  @moduledoc """
  Async background GenServer for cross-session memory distillation.

  After each conversation ends, the enqueue is called from the agent runtime.
  Distiller processes each session asynchronously via
  KnowledgeWiki.ingest_conversation/1, which extracts facts/preferences/
  tasks via LLM and writes them to knowledge_entries. Processed sessions
  are recorded in distillation_log to prevent re-processing.

  Processing is done in a Task so the GenServer mailbox is never blocked.
  """

  use GenServer
  require Logger

  alias AIBrain.Repo

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc "Enqueue a session_id for distillation. Returns :ok immediately."
  def enqueue(server \\ __MODULE__, session_id) when is_binary(session_id) do
    GenServer.cast(server, {:enqueue, session_id})
  end

  @doc "Check if a session has already been distilled (queries DB directly)."
  def already_distilled?(session_id) do
    case Repo.query(
           "SELECT entry_count FROM distillation_log WHERE session_id = ?",
           [session_id]
         ) do
      {:ok, %{rows: [[entry_count]]}} ->
        # Re-distill if session has more messages than last distillation
        message_count = session_message_count(session_id)
        message_count > 0 and message_count <= entry_count + 5

      _ ->
        false
    end
  end

  defp session_message_count(session_id) do
    try do
      store = AIBrain.Config.session_store()

      case store.load_session(store, session_id) do
        {:ok, session} -> length(session.messages)
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end

  @doc "Record a completed distillation in distillation_log (safe — wraps DB errors)."
  def record_distillation(session_id, entry_count) do
    try do
      Repo.query!(
        "INSERT OR REPLACE INTO distillation_log (session_id, distilled_at, entry_count, status) VALUES (?, ?, ?, 'done')",
        [session_id, DateTime.utc_now() |> to_string(), entry_count]
      )
    rescue
      e ->
        Logger.error(
          "Memory.Distiller.record_distillation failed for session #{session_id}: #{Exception.message(e)}"
        )
    end

    :ok
  end

  @impl true
  def init(:ok) do
    {:ok, %{queue: :queue.new()}}
  end

  @impl true
  def handle_cast({:enqueue, session_id}, state) do
    if already_distilled?(session_id) do
      Logger.debug("Memory.Distiller: skipping already-distilled session #{session_id}")
      {:noreply, state}
    else
      new_queue = :queue.in(session_id, state.queue)
      send(self(), :process_next)
      {:noreply, %{state | queue: new_queue}}
    end
  end

  @impl true
  def handle_info(:process_next, state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {:noreply, state}

      {{:value, session_id}, remaining_queue} ->
        # Run in Task to avoid blocking the GenServer mailbox
        Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn -> distill_session(session_id) end)

        unless :queue.is_empty(remaining_queue) do
          send(self(), :process_next)
        end

        {:noreply, %{state | queue: remaining_queue}}
    end
  end

  @impl true
  def handle_info(:run_episodic_batch, state) do
    # Run episodic batch asynchronously
    Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn -> run_episodic_batch() end)
    {:noreply, state}
  end

  @doc """
  Run episodic batch distillation: fetch undistilled events, group by goal_id,
  generate episodic memory records via LLM, and mark events as distilled.

  Dual trigger:
  - Quantity: called by EventStore when ≥100 undistilled events accumulate
  - Time: called by the schedules/automation engine periodically
  - Forced: when >1000 undistilled events exist (emergency cleanup)
  """
  def run_episodic_batch do
    Logger.info("Memory.Distiller: running episodic batch")

    try do
      # Check total count of undistilled events
      total_count = AIBrain.Data.Events.count_undistilled()

      # If we have >1000 undistilled events, this is a forced batch to prevent memory leak
      is_forced = total_count > 1000

      if is_forced do
        Logger.warning(
          "Memory.Distiller: FORCED batch - #{total_count} undistilled events exceeds threshold of 1000"
        )
      end

      # In forced mode, process all events (up to 2000). In normal mode, process up to 500.
      limit = if is_forced, do: 2000, else: 500
      events = AIBrain.Data.Events.list_undistilled(limit)

      if events == [] do
        Logger.debug("Memory.Distiller: no undistilled events to process")
        :ok
      else
        grouped = Enum.group_by(events, & &1.goal_id)

        Logger.info(
          "Memory.Distiller: processing #{length(events)} events across #{map_size(grouped)} goal(s)"
        )

        # Goal-scoped episodes
        grouped
        |> Enum.reject(fn {goal_id, _} -> is_nil(goal_id) end)
        |> Enum.each(fn {goal_id, goal_events} ->
          Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
            distill_goal_episode(goal_id, goal_events)
          end)
        end)

        # Orphan episode (events with no goal_id)
        orphan_events = Map.get(grouped, nil, [])

        if orphan_events != [] do
          Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
            distill_orphan_episode(orphan_events)
          end)
        end

        # Mark events as distilled
        event_ids = Enum.map(events, & &1.id)
        AIBrain.Data.Events.mark_distilled(event_ids)
        Logger.info("Memory.Distiller: marked #{length(event_ids)} events as distilled")

        # If this was a forced batch and there are still >500 events remaining, trigger another batch
        if is_forced do
          remaining = AIBrain.Data.Events.count_undistilled()

          if remaining > 500 do
            Logger.info(
              "Memory.Distiller: forced batch complete, #{remaining} events remaining - scheduling next batch"
            )

            send(self(), :run_episodic_batch)
          end
        end
      end
    rescue
      e ->
        Logger.error("Memory.Distiller: episodic batch failed: #{Exception.message(e)}")
    end

    :ok
  end

  defp distill_goal_episode(goal_id, events) do
    Logger.info(
      "Memory.Distiller: generating episode for goal #{goal_id} (#{length(events)} events)"
    )

    # Build a summary of events for this goal
    event_types = Enum.map(events, & &1.event_type) |> Enum.uniq()
    event_count = length(events)
    event_start = List.first(events)
    event_end = List.last(events)

    # Format events for LLM summarization
    formatted = format_events_for_summary(events)

    # Generate episode via LLM
    episode =
      try do
        generate_episode_via_llm(goal_id, formatted)
      rescue
        e ->
          Logger.warning(
            "Memory.Distiller: LLM episode generation failed for goal #{goal_id}: #{Exception.message(e)}"
          )

          %{
            narrative:
              "Goal #{goal_id} progress: #{event_count} events, types: #{Enum.join(event_types, ", ")}",
            objective: "",
            approach: "",
            key_decisions: [],
            success_score: 0.5,
            lessons: [],
            difficulties: %{},
            tool_usage_summary: %{},
            importance_score: min(1.0, event_count / 100)
          }
      end

    # Write episode to DB
    attrs =
      %{
        goal_id: goal_id,
        task_id: Map.get(event_end, :task_id),
        run_id: Map.get(event_end, :run_id),
        event_start_id: event_start.id,
        event_end_id: event_end.id,
        period_start: event_start.inserted_at,
        period_end: event_end.inserted_at,
        tags: event_types
      }
      |> Map.merge(
        Map.take(episode, [
          :narrative,
          :objective,
          :approach,
          :key_decisions,
          :success_score,
          :lessons,
          :difficulties,
          :tool_usage_summary,
          :importance_score
        ])
      )

    case AIBrain.Data.EpisodicMemories.create(attrs) do
      {:ok, record} ->
        Logger.info("Memory.Distiller: created episode #{record.id} for goal #{goal_id}")

      {:error, changeset} ->
        Logger.error("Memory.Distiller: failed to create episode: #{inspect(changeset.errors)}")
    end
  end

  defp distill_orphan_episode(events) do
    Logger.info("Memory.Distiller: generating orphan episode (#{length(events)} events)")

    event_types = Enum.map(events, & &1.event_type) |> Enum.uniq()
    event_start = List.first(events)
    event_end = List.last(events)
    formatted = format_events_for_summary(events)

    episode =
      try do
        generate_episode_via_llm(nil, formatted)
      rescue
        e ->
          Logger.warning(
            "Memory.Distiller: LLM episode generation failed for general session: #{Exception.message(e)}"
          )

          %{
            narrative:
              "General activity: #{length(events)} events, types: #{Enum.join(event_types, ", ")}",
            objective: "",
            approach: "",
            key_decisions: [],
            success_score: 0.5,
            lessons: [],
            difficulties: %{},
            tool_usage_summary: %{},
            importance_score: min(1.0, length(events) / 100)
          }
      end

    attrs =
      %{
        goal_id: nil,
        event_start_id: event_start.id,
        event_end_id: event_end.id,
        period_start: event_start.inserted_at,
        period_end: event_end.inserted_at,
        tags: event_types
      }
      |> Map.merge(
        Map.take(episode, [
          :narrative,
          :objective,
          :approach,
          :key_decisions,
          :success_score,
          :lessons,
          :difficulties,
          :tool_usage_summary,
          :importance_score
        ])
      )

    case AIBrain.Data.EpisodicMemories.create(attrs) do
      {:ok, record} ->
        Logger.info("Memory.Distiller: created orphan episode #{record.id}")

      {:error, changeset} ->
        Logger.error(
          "Memory.Distiller: failed to create orphan episode: #{inspect(changeset.errors)}"
        )
    end
  end

  defp format_events_for_summary(events) do
    events
    # Limit to 100 for LLM input
    |> Enum.take(100)
    |> Enum.map(fn e ->
      %{
        type: e.event_type,
        source: e.source,
        payload: e.payload,
        at: e.inserted_at
      }
    end)
  end

  defp generate_episode_via_llm(goal_id, formatted_events) do
    prompt = build_episode_prompt(goal_id, formatted_events)

    try do
      case AIBrain.LLM.SimpleChat.call(prompt) do
        {:ok, response} ->
          parse_episode_response(response)

        _ ->
          fallback_episode(goal_id, formatted_events)
      end
    rescue
      e ->
        Logger.warning(
          "Memory.Distiller.generate_episode_via_llm crashed: #{Exception.message(e)}"
        )

        fallback_episode(goal_id, formatted_events)
    end
  end

  defp build_episode_prompt(goal_id, formatted_events) do
    events_json = Jason.encode!(formatted_events, pretty: true)
    goal_label = if goal_id, do: ~s(goal "#{goal_id}"), else: "general (no specific goal)"

    """
    You are an episodic memory distiller. Your task is to analyze a sequence of events
    for #{goal_label} and produce a structured summary.

    Events:
    #{String.slice(events_json, 0, 4000)}

    Respond with a JSON object (no markdown) containing:
    {
      "narrative": "natural language summary of what happened",
      "objective": "the explicit goal or objective during this episode",
      "approach": "the high-level approach taken",
      "key_decisions": [{"decision": "", "rationale": "", "alternatives": "", "outcome": ""}],
      "success_score": 0.0-1.0,
      "lessons": ["lesson 1", "lesson 2"],
      "difficulties": {"obstacle": "resolution"},
      "tool_usage_summary": {"tool_name": count},
      "importance_score": 0.0-1.0
    }
    """
  end

  defp parse_episode_response(response) do
    # Try to extract JSON from response
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\s*/i, "")
      |> String.replace(~r/\s*```$/, "")

    case Jason.decode(cleaned) do
      {:ok, data} ->
        data
        |> Map.take([
          "narrative",
          "objective",
          "approach",
          "key_decisions",
          "success_score",
          "lessons",
          "difficulties",
          "tool_usage_summary",
          "importance_score"
        ])
        |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
        |> Map.new()

      {:error, _} ->
        %{
          narrative: String.slice(cleaned, 0, 500),
          objective: "",
          approach: "",
          key_decisions: [],
          success_score: 0.5,
          lessons: [],
          difficulties: %{},
          tool_usage_summary: %{},
          importance_score: 0.5
        }
    end
  end

  defp fallback_episode(goal_id, formatted_events) do
    event_count = length(formatted_events)
    event_types = Enum.map(formatted_events, & &1[:type]) |> Enum.uniq()

    %{
      narrative:
        "Completed #{event_count} events during goal #{goal_id}: #{Enum.join(event_types, ", ")}",
      objective: "",
      approach: "",
      key_decisions: [],
      success_score: 0.5,
      lessons: [],
      difficulties: %{},
      tool_usage_summary: %{},
      importance_score: min(1.0, event_count / 100)
    }
  end

  defp distill_session(session_id) do
    Logger.info("Memory.Distiller: distilling session #{session_id}")

    try do
      {:ok, count} = AIBrain.KnowledgeWiki.ingest_conversation(session_id)
      record_distillation(session_id, count)
      Logger.info("Memory.Distiller: distilled #{count} entries from session #{session_id}")
    rescue
      e ->
        Logger.error(
          "Memory.Distiller: failed to distill session #{session_id}: #{Exception.message(e)}"
        )
    end
  end

  @doc """
  Extract aggregated lessons from all episodic memories for a goal.
  Deduplicates similar lessons and returns them sorted by recency.

  Returns a list of lesson strings.
  """
  def goal_lessons(goal_id, opts \\ []) when is_binary(goal_id) do
    limit = Keyword.get(opts, :limit, 10)
    episodes = AIBrain.Data.EpisodicMemories.get_by_goal(goal_id, limit: limit)

    episodes
    |> Enum.flat_map(&(&1.lessons || []))
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> dedup_lessons()
    |> Enum.take(limit)
  end

  @doc """
  Build a memory context string for injection into system prompts.
  Includes recent goal lessons and key decisions from past runs.
  """
  def memory_context(goal_id, opts \\ []) when is_binary(goal_id) do
    limit = Keyword.get(opts, :limit, 3)
    episodes = AIBrain.Data.EpisodicMemories.get_by_goal(goal_id, limit: limit)

    if episodes == [] do
      ""
    else
      parts =
        episodes
        |> Enum.take(limit)
        |> Enum.map(fn ep ->
          lines = ["[Episode #{String.slice(ep.id, 0, 8)}] score=#{ep.success_score}"]

          lines =
            if ep.narrative,
              do: lines ++ ["summary: #{String.slice(ep.narrative, 0, 300)}"],
              else: lines

          lessons = (ep.lessons || []) |> Enum.reject(&(&1 == ""))

          lines =
            if lessons != [], do: lines ++ ["lessons: #{Enum.join(lessons, "; ")}"], else: lines

          Enum.join(lines, "\n")
        end)

      "## Memory: Goal History (#{length(episodes)} episodes)\n" <>
        Enum.join(parts, "\n\n")
    end
  end

  @doc """
  Merge a set of lessons across episodes, removing near-duplicates.
  Normalizes whitespace and lowercases for comparison.
  """
  def dedup_lessons(lessons, threshold \\ 0.7) when is_list(lessons) do
    lessons
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce([], fn lesson, acc ->
      lesson_lower = String.downcase(lesson)

      similar? =
        Enum.any?(acc, fn existing ->
          jaccard_sim(String.downcase(existing), lesson_lower) > threshold
        end)

      if similar?, do: acc, else: acc ++ [lesson]
    end)
  end

  defp jaccard_sim(a, b) do
    a_words = a |> String.split() |> MapSet.new()
    b_words = b |> String.split() |> MapSet.new()

    intersection = MapSet.intersection(a_words, b_words) |> MapSet.size()
    union = MapSet.union(a_words, b_words) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end
end
