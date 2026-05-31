defmodule AIBrain.Context.Layers do
  @moduledoc """
  Context layer builder — strict functional style.

  Builds the context injected alongside the core system prompt:
  user profile, relevant knowledge, temporal context, conversation
  summary, and pending situational awareness.
  """

  defstruct [
    :core,
    :user_profile,
    :knowledge,
    :temporal,
    :conversation_summary,
    :pending
  ]

  @type t :: %__MODULE__{
          core: String.t(),
          user_profile: String.t() | nil,
          knowledge: String.t() | nil,
          temporal: String.t() | nil,
          conversation_summary: String.t() | nil,
          pending: String.t() | nil
        }

  @doc """
  Build all context layers.
  """
  def build_all(messages, opts) do
    user_text = extract_last_user_text(messages)

    %__MODULE__{
      core: build_core_layer(opts),
      user_profile: build_user_profile_layer(opts),
      knowledge: build_knowledge_layer(messages, user_text, opts),
      temporal: build_temporal_layer(),
      conversation_summary: build_conversation_summary_layer(opts),
      pending: build_pending_layer()
    }
  end

  @doc """
  Compose layers into final system prompt with budget allocation.
  """
  def compose(%__MODULE__{} = layers, opts) do
    model = Keyword.get(opts, :model)
    limit = context_limit(model)
    budget = round(limit * 0.75)

    layer_order = [
      :core,
      :user_profile,
      :knowledge,
      :temporal,
      :conversation_summary,
      :pending
    ]

    layer_ratios = %{
      core: 0.40,
      user_profile: 0.08,
      knowledge: 0.22,
      temporal: 0.05,
      conversation_summary: 0.10,
      pending: 0.05
    }

    {prompt, _remaining} =
      Enum.reduce(layer_order, {"", budget}, fn key, {acc, remaining} ->
        content = Map.get(layers, key)

        if is_nil(content) or content == "" do
          {acc, remaining}
        else
          layer_budget = round(budget * Map.get(layer_ratios, key, 0.10))
          allocated = min(layer_budget, remaining)

          content = fit_to_budget(content, allocated)
          section = format_section(key, content)

          new_acc = if acc == "", do: section, else: acc <> "\n\n---\n\n#{section}"
          tokens_used = estimate_tokens(section)
          {new_acc, remaining - tokens_used}
        end
      end)

    prompt
  end

  # ── Layer Builders ─────────────────────────────────────────────

  defp build_core_layer(opts) do
    spec = Keyword.get(opts, :assistant_spec)
    context = Keyword.get(opts, :context, %{})

    prompt_ctx = %{
      required_skills: extract_skills(spec),
      goal_id: Map.get(context, :goal_id)
    }

    if spec do
      AIBrain.Agent.Prompt.build(prompt_ctx)
    else
      Keyword.get(opts, :system) || AIBrain.Agent.Prompt.build(prompt_ctx)
    end
  end

  defp extract_skills(nil), do: []
  defp extract_skills(spec), do: Map.get(spec, :skill_names, [])

  defp build_user_profile_layer(opts) do
    case AIBrain.User.profile_text() do
      "" -> build_workspace_profile(opts)
      profile -> profile
    end
  end

  defp build_workspace_profile(opts) do
    context = Keyword.get(opts, :context, %{})
    cwd = context[:cwd]

    if cwd && is_binary(cwd) && cwd != "" do
      name = cwd |> String.trim_trailing("/") |> Path.split() |> List.last() || "Project"

      "You are working in the project \"#{name}\" located at #{cwd}. All file operations are scoped to this directory."
    else
      nil
    end
  end

  defp build_knowledge_layer(_messages, query, opts) do
    if query == "" do
      build_goal_memory_layer(opts)
    else
      goal_memory = build_goal_memory_layer(opts)
      knowledge = search_knowledge(query)
      failures = search_failure_patterns(query)

      combine_layers([goal_memory, knowledge, failures])
    end
  end

  defp build_goal_memory_layer(opts) do
    context = Keyword.get(opts, :context, %{})
    goal_id = Map.get(context, :goal_id) || Map.get(context, "goal_id")

    case goal_id do
      value when is_binary(value) and value != "" ->
        case AIBrain.Memory.recall(value, type: :episodic, limit: 5) do
          {:ok, entries} when entries != [] ->
            AIBrain.Memory.context_text(entries)

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp search_knowledge(query) do
    case AIBrain.Memory.recall(query, limit: 8) do
      {:ok, entries} when is_list(entries) ->
        AIBrain.Memory.context_text(entries)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp search_failure_patterns(query) do
    entries = AIBrain.KnowledgeWiki.query_by_relevance(query, limit: 3, type: "failure_pattern")

    if entries == [] do
      nil
    else
      lines = Enum.map(entries, fn e -> "⚠️ #{e.content}" end)

      "## Lessons from Past Failures\nThe following are known issues/pitfalls. Avoid repeating these:\n" <>
        Enum.join(lines, "\n")
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp build_temporal_layer do
    temporal = AIBrain.Memory.Temporal.build_context()
    recent = AIBrain.Memory.Temporal.format_recent_activity()

    combine_layers([temporal, recent])
  rescue
    _ -> nil
  end

  defp build_conversation_summary_layer(opts) do
    session_id = Keyword.get(opts, :session_id)

    if session_id do
      case AIBrain.ConversationLog.get_base_context(session_id) do
        {:ok, summary} when is_binary(summary) and summary != "" -> summary
        _ -> nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp build_pending_layer do
    clues = build_pending_clues()

    if clues == [] do
      nil
    else
      text =
        "## Situational Awareness\n\n" <>
          "The following items may need your attention. Mention them naturally if relevant:\n" <>
          Enum.join(clues, "\n") <>
          "\n\nDon't force these into conversation. Only bring up when it flows naturally."

      text
    end
  rescue
    _ -> nil
  end

  defp build_pending_clues do
    stale_tasks = fetch_stale_tasks()
    active_goals = fetch_active_goals()

    stale_tasks ++ active_goals
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  defp fetch_stale_tasks do
    tasks = AIBrain.Data.Tasks.list_pending_dispatchable()
    stalled = Enum.filter(tasks, &stale?(&1.updated_at || &1.inserted_at, 2))

    if stalled != [] do
      count = length(stalled)
      names = Enum.map_join(stalled, ", ", & &1.title)

      [
        "- #{count} pending task(s) stalled: #{names}. Ask if the user wants to continue or adjust."
      ]
    else
      []
    end
  rescue
    _ -> []
  end

  defp fetch_active_goals do
    {:ok, goals} = AIBrain.Data.Goals.list(status: "active")
    old_goals = Enum.filter(goals, &stale?(&1.updated_at || &1.inserted_at, 3))

    if old_goals != [] do
      names = Enum.map_join(old_goals, ", ", & &1.title)
      ["- Active goal(s) without recent progress: #{names}. Remind the user these goals exist."]
    else
      []
    end
  rescue
    _ -> []
  end

  defp stale?(nil, _), do: false

  defp stale?(dt, days) do
    DateTime.diff(DateTime.utc_now(), dt, :day) >= days
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp extract_last_user_text(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: "user", content: content} when is_binary(content) -> content
      %{role: "user", content: [%{type: "text", text: text}]} -> text
      _ -> nil
    end)
  end

  defp combine_layers(layers) do
    layers
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      non_empty -> Enum.join(non_empty, "\n\n")
    end
  end

  defp format_section(:core, content), do: content
  defp format_section(key, content), do: "## #{layer_header(key)}\n\n#{content}"

  defp layer_header(:user_profile), do: "User Profile"
  defp layer_header(:knowledge), do: "Reference Knowledge"
  defp layer_header(:temporal), do: "Temporal Context"
  defp layer_header(:conversation_summary), do: "Previous Conversation Summary"
  defp layer_header(:pending), do: "Pending Awareness"
  defp layer_header(key), do: to_string(key)

  defp fit_to_budget(content, max_tokens) do
    estimated = estimate_tokens(content)

    if estimated <= max_tokens do
      content
    else
      max_chars = max_tokens * 4

      if max_chars < 100 do
        ""
      else
        String.slice(content, 0, max_chars) <> "\n[...truncated to fit context budget]"
      end
    end
  end

  defp estimate_tokens(text) do
    AIBrain.LLM.Context.estimate_tokens(text)
  end

  defp context_limit(model) when is_binary(model) do
    AIBrain.LLM.Context.context_limit(model)
  end

  defp context_limit(_), do: 128_000
end
