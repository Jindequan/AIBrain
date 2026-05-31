defmodule AIBrain.Permissions.Diagnostics do
  @moduledoc """
  Builds operator-facing diagnostics from permission events.
  """

  def summarize(events) when is_list(events) do
    permission_events =
      Enum.filter(events, fn
        %{type: :permission_checked} -> true
        _ -> false
      end)

    denied =
      Enum.filter(permission_events, fn event ->
        Map.get(event, :decision) == :denied or Map.get(event, "decision") == :denied
      end)

    approved =
      Enum.filter(permission_events, fn event ->
        Map.get(event, :decision) == :approved or Map.get(event, "decision") == :approved
      end)

    %{
      counts: %{approved: length(approved), denied: length(denied)},
      denials: Enum.map(denied, &normalize_denial/1)
    }
  end

  def summarize(_events), do: %{counts: %{approved: 0, denied: 0}, denials: []}

  defp normalize_denial(event) do
    %{
      tool_name: Map.get(event, :tool_name) || Map.get(event, "tool_name"),
      reason: Map.get(event, :reason) || Map.get(event, "reason"),
      mode: Map.get(event, :mode) || Map.get(event, "mode"),
      severity: :warning
    }
  end
end
