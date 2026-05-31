defmodule AIBrain.Permissions.Policy do
  @moduledoc """
  Central policy gate for tool execution.
  """

  alias AIBrain.Permissions.Modes
  alias AIBrain.Tool.Registry

  def authorize(tool_use, registry, opts \\ []) do
    mode = Modes.normalize(Keyword.get(opts, :mode))
    resolver = Keyword.get(opts, :approval_resolver)
    risk = Registry.risk_category(registry, tool_use.name)

    case mode do
      :execute ->
        {:allow, tool_use, %{decision: :allowed, reason: :execute_mode, risk: risk, mode: mode}}

      :plan ->
        if risk == :read_only do
          {:allow, tool_use,
           %{decision: :allowed, reason: :plan_mode_read_only, risk: risk, mode: mode}}
        else
          {:deny, denied_message(tool_use.name, :plan_mode),
           %{decision: :denied, reason: :plan_mode, risk: risk, mode: mode}}
        end

      :approval_required ->
        if risk == :read_only do
          {:allow, tool_use, %{decision: :allowed, reason: :read_only, risk: risk, mode: mode}}
        else
          case resolve_approval(tool_use, resolver) do
            :approve ->
              {:allow, tool_use,
               %{decision: :approved, reason: :approval_granted, risk: risk, mode: mode}}

            {:deny, reason} ->
              {:deny, denied_message(tool_use.name, reason),
               %{decision: :denied, reason: reason, risk: risk, mode: mode}}

            :deny ->
              {:deny, denied_message(tool_use.name, :approval_denied),
               %{decision: :denied, reason: :approval_denied, risk: risk, mode: mode}}
          end
        end
    end
  end

  defp resolve_approval(_tool_use, nil), do: {:deny, :approval_required}

  defp resolve_approval(tool_use, resolver) when is_function(resolver, 1) do
    case resolver.(tool_use) do
      true -> :approve
      false -> :deny
      other -> other
    end
  end

  defp denied_message(tool_name, reason) do
    "Tool #{tool_name} blocked: #{reason}"
  end
end
