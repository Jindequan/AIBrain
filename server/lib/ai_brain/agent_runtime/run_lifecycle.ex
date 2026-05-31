defmodule AIBrain.AgentRuntime.RunLifecycle do
  @moduledoc """
  Explicit lifecycle operations for the unified `runs` ER model.

  The database stores lifecycle state, normalized references, small summaries,
  and paths. Large messages, events, and final outputs stay in the run folder.
  """

  require Logger

  alias AIBrain.AgentRuntime.{FileStore, RunRequest}
  alias AIBrain.Data.{Events, RunContextRefs, Runs, RunSteps}

  @terminal_statuses ~w(completed completed_with_warnings failed cancelled)

  def terminal_statuses, do: @terminal_statuses

  @max_inline_output 4_000

  def create(%RunRequest{} = request) do
    run_id = request.id || AIBrain.Session.ShortID.run_id()

    needs_files = needs_file_storage?(request)

    if needs_files do
      FileStore.ensure_run_dir(run_id)
    end

    attrs = %{
      id: run_id,
      source_type: request.source_type,
      source_id: request.source_id || inferred_source_id(request),
      status: "pending",
      phase: "context",
      mode: request.mode,
      objective: request.objective,
      title: request.title || title_from_objective(request.objective),
      parent_run_id: request.parent_run_id,
      autonomy_level: request.autonomy_level,
      workspace_path: request.workspace_path,
      model: request.model,
      messages_path: if(needs_files, do: FileStore.messages_path(run_id)),
      input: %{"objective" => request.objective},
      metadata: request.metadata || %{}
    }

    with {:ok, run} <- Runs.create_run(attrs),
         :ok <- RunContextRefs.create_many(run.id, RunRequest.context_refs(request)) do
      if needs_files do
        step(run.id, "context", "completed", "system", "Run created", %{
          summary: "Run request normalized and persisted.",
          output_path: attrs[:messages_path]
        })
      end

      event(
        run.id,
        "run.created",
        %{source_type: run.source_type, source_id: run.source_id},
        request
      )

      {:ok, run}
    end
  end

  def start(run_id, %RunRequest{} = request) do
    if terminal?(run_id) do
      {:error, :already_terminal}
    else
      do_start(run_id, request)
    end
  end

  defp do_start(run_id, %RunRequest{} = request) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Runs.transition_from(run_id, "pending", "running", %{
           phase: "executing",
           started_at: now
         }) do
      {:ok, 1} ->
        event(run_id, "run.started", %{mode: request.mode}, request)
        :ok

      {:ok, 0} ->
        {:error, :not_pending}
    end
  end

  def complete(run_id, text, %RunRequest{} = request) when is_binary(text) do
    unless terminal?(run_id) do
      {summary, output_path} = do_complete(run_id, text)
      event(run_id, "run.completed", %{summary: summary}, request)
      {:ok, summary, output_path}
    else
      :ok
    end
  end

  def complete(run_id, text, attrs) when is_binary(text) and is_map(attrs) do
    unless terminal?(run_id) do
      {summary, output_path} = do_complete(run_id, text)
      event(run_id, "run.completed", %{summary: summary}, attrs)
      {:ok, summary, output_path}
    else
      :ok
    end
  end

  def fail(run_id, reason, %RunRequest{} = request) do
    unless terminal?(run_id) do
      error = do_fail(run_id, reason)
      event(run_id, "run.failed", %{error: error}, request)
    end

    :ok
  end

  def fail(run_id, reason, attrs) when is_map(attrs) do
    unless terminal?(run_id) do
      error = do_fail(run_id, reason)
      event(run_id, "run.failed", %{error: error}, attrs)
    end

    :ok
  end

  def cancel(run_id, attrs \\ %{}) do
    case Runs.get_run(run_id) do
      {:ok, run} when run.status in @terminal_statuses ->
        {:ok, run}

      {:ok, _run} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        case Runs.transition_not_terminal(run_id, "cancelled", %{
               phase: "cancelled",
               completed_at: now
             }) do
          {:ok, 1} ->
            RunSteps.cancel_open(run_id, "Run cancelled.")

            step(run_id, "cancelled", "cancelled", "system", "Run cancelled", %{
              summary: Map.get(attrs, :summary, "Run was cancelled."),
              metadata: safe_event_payload(attrs)
            })

          {:ok, 0} ->
            Runs.get_run(run_id)
        end

      error ->
        error
    end
  end

  def recover_interrupted do
    Runs.list_runs(status: ["running"])
    |> Enum.each(fn run ->
      # Check if the run actually completed (output file exists from save_result).
      # This covers the crash window between Executor completion and Orchestrator finalization.
      output_exists? =
        is_binary(run.output_path) and run.output_path != "" and File.exists?(run.output_path)

      if output_exists? do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        case FileStore.read_output(run.id) do
          {:ok, text} ->
            Runs.update_run(run.id, %{
              status: "completed",
              phase: "completed",
              output_summary: summarize(text),
              output_path: run.output_path,
              completed_at: now
            })

            Logger.info("RunLifecycle: recovered run #{run.id} as completed from output file")

          _ ->
            mark_unrecoverable(run, "output file unreadable")
        end
      else
        case FileStore.load_messages(run.id) do
          {:ok, []} ->
            mark_unrecoverable(run, "no persisted messages")

          {:ok, _messages} ->
            mark_unrecoverable(run, "rebuild not yet implemented")

          {:error, reason} ->
            mark_unrecoverable(run, "messages unreadable: #{inspect(reason)}")
        end
      end
    end)

    # Pending runs at boot never started — mark failed.
    Runs.list_runs(status: ["pending"])
    |> Enum.each(fn run ->
      mark_unrecoverable(run, "never started")
    end)
  end

  defp mark_unrecoverable(run, reason) do
    Logger.warning("RunLifecycle: run #{run.id} unrecoverable: #{reason}")

    Runs.update_run(run.id, %{
      status: "failed",
      phase: "failed",
      error: "restart_recovery: #{reason}",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    step(run.id, "recovery", "failed", "system", "Restart recovery failed", %{
      summary: "Run could not be rebuilt after restart: #{reason}",
      metadata: %{
        messages_path: run.messages_path,
        events_path: Path.join(FileStore.run_dir(run.id), "events.jsonl"),
        output_path: run.output_path
      }
    })
  end

  def step(run_id, phase, status, kind, title, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:run_id, run_id)
      |> Map.put(:step_index, RunSteps.next_index(run_id))
      |> Map.put(:phase, phase)
      |> Map.put(:status, status)
      |> Map.put(:kind, kind)
      |> Map.put(:title, title)

    case RunSteps.create(attrs) do
      {:ok, step} ->
        step

      {:error, changeset} ->
        Logger.warning("RunLifecycle: failed to record step: #{inspect(changeset.errors)}")
        nil
    end
  rescue
    e ->
      Logger.warning("RunLifecycle: failed to record step: #{Exception.message(e)}")
      nil
  end

  def event(run_id, event_type, payload, %RunRequest{} = request) do
    Events.create(%{
      correlation_id: run_id,
      event_type: event_type,
      source: "agent_runtime",
      payload: safe_event_payload(payload),
      metadata: %{mode: request.mode, source_type: request.source_type},
      session_id: request.session_id,
      goal_id: request.goal_id,
      task_id: request.task_id,
      run_id: run_id,
      importance: 0.5,
      token_count: 0
    })

    :ok
  rescue
    e ->
      Logger.warning(
        "RunLifecycle: failed to record event #{event_type}: #{Exception.message(e)}"
      )

      :ok
  end

  def event(run_id, event_type, payload, attrs) when is_map(attrs) do
    metadata = safe_event_payload(attrs)

    Events.create(%{
      correlation_id: run_id,
      event_type: event_type,
      source: metadata["source"] || "agent_runtime",
      payload: safe_event_payload(payload),
      metadata: metadata,
      session_id: metadata["session_id"],
      goal_id: metadata["goal_id"],
      task_id: metadata["task_id"],
      run_id: run_id,
      importance: 0.5,
      token_count: 0
    })

    :ok
  rescue
    e ->
      Logger.warning(
        "RunLifecycle: failed to record event #{event_type}: #{Exception.message(e)}"
      )

      :ok
  end

  def safe_event_payload(payload) when is_map(payload), do: stringify_keys(payload)
  def safe_event_payload(payload), do: %{"value" => inspect(payload)}

  def summarize(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 1_000)
  end

  def summarize(_), do: ""

  def stringify(value) when is_binary(value), do: value
  def stringify(value), do: inspect(value)

  defp do_complete(run_id, text) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    summary = summarize(text)
    status = completion_status(run_id)

    {:ok, run} = Runs.get_run(run_id)
    has_files = is_binary(run.messages_path) and run.messages_path != ""
    large = byte_size(text) > @max_inline_output

    {output_attrs, output_path} =
      if has_files or large do
        {:ok, path} = FileStore.write_output(run_id, text)
        {%{output: nil, output_path: path}, path}
      else
        {%{output: text, output_path: nil}, nil}
      end

    case Runs.transition_not_terminal(
           run_id,
           status,
           Map.merge(output_attrs, %{
             phase: "completed",
             output_summary: summary,
             completed_at: now
           })
         ) do
      {:ok, 1} ->
        if output_path do
          step(run_id, "reporting", "completed", "report", "Final report", %{
            summary: summary,
            output_path: output_path
          })
        end

        {summary, output_path}

      {:ok, 0} ->
        {summary, output_path}
    end
  end

  defp completion_status(_run_id), do: "completed"

  defp do_fail(run_id, reason) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    error = stringify(reason)

    Runs.transition_not_terminal(run_id, "failed", %{
      phase: "failed",
      error: error,
      completed_at: now
    })

    error
  end

  defp inferred_source_id(request) do
    request.task_id || request.goal_id || request.schedule_id || request.session_id
  end

  defp title_from_objective(objective) do
    objective
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 80)
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), safe_value(v)}
      {k, v} -> {to_string(k), safe_value(v)}
    end)
  rescue
    _ -> %{"value" => inspect(map)}
  end

  defp safe_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp safe_value(nil), do: nil
  defp safe_value(%{__struct__: _} = value), do: inspect(value)
  defp safe_value(value) when is_map(value), do: stringify_keys(value)
  defp safe_value(value) when is_list(value), do: Enum.map(value, &safe_value/1)

  defp safe_value(value) when is_binary(value) and byte_size(value) > 2_000,
    do: String.slice(value, 0, 2_000)

  defp safe_value(value) when is_tuple(value), do: inspect(value)
  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value), do: value

  defp terminal?(run_id) do
    case Runs.get_run(run_id) do
      {:ok, run} -> run.status in @terminal_statuses
      _ -> false
    end
  end

  # Only async/background runs need file storage for recovery.
  # Interactive chat runs have conversation.log as the source of truth.
  @file_modes ~w(background goal_tick scheduled)

  defp needs_file_storage?(%RunRequest{mode: mode}) do
    mode in @file_modes
  end
end
