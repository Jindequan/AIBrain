defmodule AIBrain.Permissions.ExplainerTest do
  use ExUnit.Case, async: true

  alias AIBrain.Permissions.Explainer

  test "explain_capability_rejection/1 returns operator-facing guidance" do
    rejection = %{
      name: "workspace-kit",
      source: :project_local,
      reason: :project_local_disabled,
      explanation: "Project-local capabilities require explicit workspace trust."
    }

    assert %{
             surface: :capability,
             title: "Capability blocked",
             summary: "workspace-kit was not loaded.",
             detail: "Project-local capabilities require explicit workspace trust.",
             next_step:
               "Mark the workspace as trusted before enabling project-local capabilities."
           } = Explainer.explain_capability_rejection(rejection)
  end

  test "explain_permission_denial/1 returns tool denial guidance" do
    event = %{
      tool_name: "bash",
      decision: :denied,
      reason: :plan_mode,
      risk: :shell_exec,
      mode: :plan
    }

    assert %{
             surface: :tool_permission,
             title: "Tool blocked",
             summary: "bash was blocked in plan mode.",
             detail:
               "Shell execution is disabled until execution mode or explicit approval is granted."
           } = Explainer.explain_permission_denial(event)
  end

  test "explain_sandbox_feedback/1 returns sandbox guidance" do
    event = %{
      result: :blocked,
      operation: :workspace_write,
      detail: "Writes outside the allowed workspace are blocked."
    }

    assert %{
             surface: :sandbox,
             title: "Sandbox blocked",
             summary: "workspace_write was blocked by the sandbox.",
             detail: "Writes outside the allowed workspace are blocked.",
             next_step: "Adjust the sandbox policy or retry within the allowed workspace."
           } = Explainer.explain_sandbox_feedback(event)
  end
end
