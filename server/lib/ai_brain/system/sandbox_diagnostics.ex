defmodule AIBrain.System.SandboxDiagnostics do
  @moduledoc """
  Builds operator-facing diagnostics from sandbox feedback events.
  """

  def summarize(events) when is_list(events) do
    sandbox_events =
      Enum.filter(events, fn
        %{type: :sandbox_feedback} -> true
        _ -> false
      end)

    blocked =
      Enum.filter(sandbox_events, fn event ->
        Map.get(event, :result) == :blocked or Map.get(event, "result") == :blocked
      end)

    allowed =
      Enum.filter(sandbox_events, fn event ->
        Map.get(event, :result) == :allowed or Map.get(event, "result") == :allowed
      end)

    %{
      counts: %{allowed: length(allowed), blocked: length(blocked)},
      blocked: Enum.map(blocked, &normalize_entry/1)
    }
  end

  def summarize(_events), do: %{counts: %{allowed: 0, blocked: 0}, blocked: []}

  defp normalize_entry(event) do
    %{
      tool_use_id: Map.get(event, :tool_use_id) || Map.get(event, "tool_use_id"),
      operation: Map.get(event, :operation) || Map.get(event, "operation"),
      result: Map.get(event, :result) || Map.get(event, "result"),
      detail: Map.get(event, :detail) || Map.get(event, "detail"),
      severity: :warning
    }
  end
end
