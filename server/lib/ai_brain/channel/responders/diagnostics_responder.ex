defmodule AIBrain.Channel.Responders.DiagnosticsResponder do
  @moduledoc """
  Builds channel-friendly diagnostics summary replies.
  """

  alias AIBrain.Channel.Reply
  alias AIBrain.Telemetry.Audit

  def build_permission_summary_from_export(export) when is_map(export) do
    summary =
      export
      |> Map.get(:operator_diagnostics, Map.get(export, "operator_diagnostics", %{}))
      |> Map.get(:permissions, %{})
      |> then(fn
        %{} = permissions when map_size(permissions) > 0 -> permissions
        _ -> %{}
      end)

    text = render_permission_summary(summary)
    {:ok, Reply.build(:permission_diagnostics_summary, text)}
  end

  def build_sandbox_summary_from_export(export) when is_map(export) do
    summary = sandbox_summary(export)
    text = render_sandbox_summary(summary)
    {:ok, Reply.build(:sandbox_diagnostics_summary, text)}
  end

  def build_sandbox_entries_from_export(export) when is_map(export) do
    summary = sandbox_summary(export)
    text = render_sandbox_entries(summary)
    {:ok, Reply.build(:sandbox_feedback_entries, text)}
  end

  def build_from_session(session_store, session_id, reply_type, audit_opts \\ [])
      when is_atom(reply_type) do
    with {:ok, export} <- Audit.export_session(session_store, session_id, audit_opts) do
      case reply_type do
        :permission_diagnostics_summary -> build_permission_summary_from_export(export)
        :sandbox_diagnostics_summary -> build_sandbox_summary_from_export(export)
        :sandbox_feedback_entries -> build_sandbox_entries_from_export(export)
      end
    end
  end

  defp render_permission_summary(summary) do
    counts = Map.get(summary, :counts) || Map.get(summary, "counts") || %{}
    denials = Map.get(summary, :denials) || Map.get(summary, "denials") || []
    approved = Map.get(counts, :approved) || Map.get(counts, "approved") || 0
    denied = Map.get(counts, :denied) || Map.get(counts, "denied") || 0

    lines = [
      "Permission Diagnostics Summary",
      "Approved checks: #{approved}",
      "Denied checks: #{denied}"
    ]

    denial_lines =
      Enum.map(denials, fn denial ->
        tool_name = Map.get(denial, :tool_name) || Map.get(denial, "tool_name")
        reason = Map.get(denial, :reason) || Map.get(denial, "reason")
        mode = Map.get(denial, :mode) || Map.get(denial, "mode")
        "#{tool_name} denied: #{reason} (#{mode})"
      end)

    Enum.join(lines ++ denial_lines, "\n")
  end

  defp render_sandbox_summary(summary) do
    counts = Map.get(summary, :counts) || Map.get(summary, "counts") || %{}
    blocked = Map.get(summary, :blocked) || Map.get(summary, "blocked") || []
    allowed_count = Map.get(counts, :allowed) || Map.get(counts, "allowed") || 0
    blocked_count = Map.get(counts, :blocked) || Map.get(counts, "blocked") || 0

    lines = [
      "Sandbox Diagnostics Summary",
      "Allowed checks: #{allowed_count}",
      "Blocked checks: #{blocked_count}"
    ]

    blocked_lines =
      Enum.map(blocked, fn entry ->
        operation = Map.get(entry, :operation) || Map.get(entry, "operation")
        detail = Map.get(entry, :detail) || Map.get(entry, "detail")
        "#{operation} blocked: #{detail}"
      end)

    Enum.join(lines ++ blocked_lines, "\n")
  end

  defp render_sandbox_entries(summary) do
    blocked = Map.get(summary, :blocked) || Map.get(summary, "blocked") || []

    lines =
      Enum.flat_map(blocked, fn entry ->
        tool_use_id = Map.get(entry, :tool_use_id) || Map.get(entry, "tool_use_id")
        operation = Map.get(entry, :operation) || Map.get(entry, "operation")
        detail = Map.get(entry, :detail) || Map.get(entry, "detail")

        [
          "Sandbox Feedback Entries",
          "Tool use: #{tool_use_id}",
          "Operation: #{operation}",
          "Detail: #{detail}"
        ]
      end)

    Enum.join(if(lines == [], do: ["Sandbox Feedback Entries"], else: lines), "\n")
  end

  defp sandbox_summary(export) do
    export
    |> Map.get(:operator_diagnostics, Map.get(export, "operator_diagnostics", %{}))
    |> Map.get(:sandbox, %{})
    |> then(fn
      %{} = sandbox when map_size(sandbox) > 0 -> sandbox
      _ -> %{}
    end)
  end
end
