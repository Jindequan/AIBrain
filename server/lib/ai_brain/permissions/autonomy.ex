defmodule AIBrain.Permissions.Autonomy do
  @moduledoc """
  Maps chat autonomy levels (0–2) to tool auto-approval under `:approval_required`.

  Aligns with the frontend ChatInput presets:
    * 0 — Suggest: no tools auto-run
    * 1 — Assist: read-only tools (search, read file, etc.)
    * 2 — Execute: read + workspace write + network (shell still needs approval)
  """

  alias AIBrain.Tool.Registry

  @level_1_risks [:read_only]
  @level_2_risks [:read_only, :workspace_write, :network]

  @doc """
  Whether a tool may run without interactive approval at this autonomy level.
  """
  def auto_allowed?(level, tool_name, registry) when is_integer(level) and level >= 0 do
    risk = Registry.risk_category(registry, tool_name)
    level_allows_risk?(level, risk)
  end

  def auto_allowed?(_, _, _), do: false

  defp level_allows_risk?(0, _risk), do: false

  defp level_allows_risk?(1, risk), do: risk in @level_1_risks

  defp level_allows_risk?(level, risk) when level >= 2, do: risk in @level_2_risks

end
