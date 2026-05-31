defmodule AIBrain.Channel.Bridge do
  @moduledoc """
  Minimal bridge that converts capability status requests into published channel
  replies.
  """

  alias AIBrain.Channel.{Bus, Request}

  alias AIBrain.Channel.Responders.{
    DiagnosticsResponder,
    OperatorResponder,
    SchedulerResponder,
    TaskResponder
  }

  def dispatch(bus, request, opts \\ [])

  def dispatch(bus, request, opts) do
    with {:ok, normalized} <- Request.normalize(request),
         {:ok, reply} <- build_reply(normalized, opts) do
      enriched = attach_channel(reply, Map.get(normalized, :channel))
      :ok = Bus.publish(bus, enriched)
      {:ok, enriched}
    end
  end

  def dispatch_event(bus, event, opts \\ [])

  def dispatch_event(bus, event, opts) when is_map(event) do
    channel = Keyword.get(opts, :channel)
    dispatch(bus, Map.put(event, :channel, channel), opts)
  end

  defp build_reply(%{type: :permission_checked, decision: :suspended} = event, _opts) do
    tool_name = Map.get(event, :tool_name, "unknown")
    approval_id = Map.get(event, :approval_id)
    tool_use_id = Map.get(event, :tool_use_id)
    risk = Map.get(event, :risk)

    content = "Tool '#{tool_name}' requires approval before execution."

    {:ok,
     AIBrain.Channel.Reply.build(:approval_request, content, %{
       tool_name: tool_name,
       tool_use_id: tool_use_id,
       approval_id: approval_id,
       risk: risk
     })}
  end

  defp build_reply(%{type: :permission_checked, decision: decision} = event, _opts) do
    tool_name = Map.get(event, :tool_name, "unknown")
    reason = Map.get(event, :reason)

    content = "Tool '#{tool_name}' permission check: #{decision} (#{reason})"

    {:ok,
     AIBrain.Channel.Reply.build(:permission_checked, content, %{
       decision: decision,
       tool_name: tool_name
     })}
  end

  defp build_reply(%{type: :query_suspended} = event, _opts) do
    reason = Map.get(event, :reason, "approval_required")
    status = Map.get(event, :status, "waiting_approval")
    approval_id = Map.get(event, :approval_id)

    content = "Query suspended: #{reason}"

    {:ok,
     AIBrain.Channel.Reply.build(:query_suspended, content, %{
       reason: reason,
       status: status,
       approval_id: approval_id
     })}
  end

  defp build_reply(%{type: :permission_diagnostics_summary, export: export}, _opts)
       when is_map(export) do
    DiagnosticsResponder.build_permission_summary_from_export(export)
  end

  defp build_reply(%{type: :permission_diagnostics_summary, session_id: session_id}, opts)
       when is_binary(session_id) do
    DiagnosticsResponder.build_from_session(
      Keyword.fetch!(opts, :session_store),
      session_id,
      :permission_diagnostics_summary,
      Keyword.get(opts, :audit_opts, [])
    )
  end

  defp build_reply(%{type: :sandbox_diagnostics_summary, export: export}, _opts)
       when is_map(export) do
    DiagnosticsResponder.build_sandbox_summary_from_export(export)
  end

  defp build_reply(%{type: :sandbox_diagnostics_summary, session_id: session_id}, opts)
       when is_binary(session_id) do
    DiagnosticsResponder.build_from_session(
      Keyword.fetch!(opts, :session_store),
      session_id,
      :sandbox_diagnostics_summary,
      Keyword.get(opts, :audit_opts, [])
    )
  end

  defp build_reply(%{type: :sandbox_feedback_entries, export: export}, _opts)
       when is_map(export) do
    DiagnosticsResponder.build_sandbox_entries_from_export(export)
  end

  defp build_reply(%{type: :sandbox_feedback_entries, session_id: session_id}, opts)
       when is_binary(session_id) do
    DiagnosticsResponder.build_from_session(
      Keyword.fetch!(opts, :session_store),
      session_id,
      :sandbox_feedback_entries,
      Keyword.get(opts, :audit_opts, [])
    )
  end

  defp build_reply(
         %{type: :operator_diagnostic, diagnostic_type: :capability_rejection, payload: payload},
         _opts
       )
       when is_map(payload) do
    OperatorResponder.build_capability_rejection(payload)
  end

  defp build_reply(
         %{type: :operator_diagnostic, diagnostic_type: :permission_denial, payload: payload},
         _opts
       )
       when is_map(payload) do
    OperatorResponder.build_permission_denial(payload)
  end

  defp build_reply(
         %{type: :operator_diagnostic, diagnostic_type: :sandbox_feedback, payload: payload},
         _opts
       )
       when is_map(payload) do
    OperatorResponder.build_sandbox_feedback(payload)
  end

  defp build_reply(%{type: :scheduler_status}, opts) do
    diagnostics =
      Keyword.get(opts, :scheduler_diagnostics) || AIBrain.Data.Schedules.diagnostics()

    SchedulerResponder.build_status(
      diagnostics ||
        %{counts: %{total: 0, active: 0, paused: 0, fired: 0, cancelled: 0}, upcoming: []}
    )
  end

  defp build_reply(%{type: :task_status, task_id: task_id}, _opts) do
    case AIBrain.Data.Tasks.get_task(task_id) do
      {:ok, task} ->
        TaskResponder.build_status(task)

      {:error, :not_found} ->
        AIBrain.Channel.Reply.build(:task_status, "Task not found: #{task_id}")
    end
  end

  defp build_reply(%{type: :task_status}, _opts) do
    AIBrain.Channel.Reply.build(:task_status, "Missing task_id")
  end

  defp build_reply(%{type: :task_list}, _opts) do
    tasks = AIBrain.Data.Tasks.list_all_tasks()
    TaskResponder.build_list(tasks)
  end

  defp build_reply(%{type: :task_output, task_id: task_id}, _opts) do
    with {:ok, task} <- AIBrain.Data.Tasks.get_task(task_id),
         {:ok, output} <- task_output(task) do
      TaskResponder.build_output(task, output)
    else
      {:error, :not_found} ->
        AIBrain.Channel.Reply.build(:task_output, "Task not found: #{task_id}")
    end
  end

  defp build_reply(%{type: :task_output}, _opts) do
    AIBrain.Channel.Reply.build(:task_output, "Missing task_id")
  end

  defp build_reply(request, _opts) do
    type = Map.get(request, :type) || "unknown"
    {:ok, AIBrain.Channel.Reply.build(type, "No handler for request type: #{type}")}
  end

  defp task_output(%{run_id: run_id, output: output}) when is_binary(run_id) and run_id != "" do
    case AIBrain.AgentRuntime.FileStore.read_output(run_id) do
      {:ok, text} -> {:ok, text}
      {:error, :not_found} when is_binary(output) -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_output(%{output: output}) when is_binary(output), do: {:ok, output}
  defp task_output(_task), do: {:error, :not_found}

  defp attach_channel(reply, nil), do: reply

  defp attach_channel(reply, channel) do
    metadata =
      reply
      |> Map.get(:metadata, %{})
      |> Map.put(:channel, channel)

    Map.put(reply, :metadata, metadata)
  end
end
