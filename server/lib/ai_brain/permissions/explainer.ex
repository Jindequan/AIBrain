defmodule AIBrain.Permissions.Explainer do
  @moduledoc """
  Builds operator-facing explanations for permission and capability policy
  decisions.
  """

  def explain_capability_rejection(rejection) when is_map(rejection) do
    name = Map.get(rejection, :name) || Map.get(rejection, "name") || "Capability"
    reason = normalize_reason(Map.get(rejection, :reason) || Map.get(rejection, "reason"))

    detail =
      Map.get(rejection, :explanation) || Map.get(rejection, "explanation") ||
        "Capability loading was rejected."

    %{
      surface: :capability,
      title: "Capability blocked",
      summary: "#{name} was not loaded.",
      detail: detail,
      next_step: next_step_for_capability_reason(reason)
    }
  end

  def explain_permission_denial(event) when is_map(event) do
    tool_name = Map.get(event, :tool_name) || Map.get(event, "tool_name") || "Tool"
    reason = normalize_reason(Map.get(event, :reason) || Map.get(event, "reason"))
    mode = normalize_reason(Map.get(event, :mode) || Map.get(event, "mode"))

    %{
      surface: :tool_permission,
      title: "Tool blocked",
      summary: "#{tool_name} was blocked in #{mode} mode.",
      detail: permission_detail(reason),
      next_step: permission_next_step(reason)
    }
  end

  def explain_sandbox_feedback(event) when is_map(event) do
    operation =
      normalize_reason(Map.get(event, :operation) || Map.get(event, "operation")) ||
        :sandbox_operation

    result = normalize_reason(Map.get(event, :result) || Map.get(event, "result")) || :blocked

    detail =
      Map.get(event, :detail) || Map.get(event, "detail") ||
        "The sandbox blocked the requested operation."

    %{
      surface: :sandbox,
      title: "Sandbox blocked",
      summary: "#{operation} was #{result} by the sandbox.",
      detail: detail,
      next_step: "Adjust the sandbox policy or retry within the allowed workspace."
    }
  end

  defp next_step_for_capability_reason(:project_local_disabled),
    do: "Mark the workspace as trusted before enabling project-local capabilities."

  defp next_step_for_capability_reason(:workspace_not_trusted),
    do: "Mark the workspace as trusted before enabling project-local capabilities."

  defp next_step_for_capability_reason(:managed_capability_locked),
    do: "Change the managed capability policy before attempting a local override."

  defp next_step_for_capability_reason(_reason),
    do: "Review capability policy settings and retry after the restriction is resolved."

  defp permission_detail(:plan_mode),
    do: "Shell execution is disabled until execution mode or explicit approval is granted."

  defp permission_detail(:approval_required),
    do: "This action requires an explicit approval step before the tool may run."

  defp permission_detail(:approval_denied),
    do: "The requested tool action was denied during approval."

  defp permission_detail(reason) when is_atom(reason),
    do: "The tool action was blocked by policy: #{Atom.to_string(reason)}."

  defp permission_next_step(:plan_mode),
    do: "Switch to execute mode or request approval before retrying the tool."

  defp permission_next_step(:approval_required),
    do: "Provide an approval resolver or operator approval before retrying the tool."

  defp permission_next_step(:approval_denied),
    do: "Adjust the request or grant approval before retrying the tool."

  defp permission_next_step(_reason),
    do: "Review the current permission mode and retry after the restriction is resolved."

  defp normalize_reason(value) when is_atom(value), do: value

  defp normalize_reason(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> String.to_atom(value)
    end
  end

  defp normalize_reason(value), do: value
end
