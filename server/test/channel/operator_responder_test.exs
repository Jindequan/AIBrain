defmodule AIBrain.Channel.Responders.OperatorResponderTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Responders.OperatorResponder

  test "build_capability_rejection/1 returns an assistant reply with operator guidance" do
    rejection = %{
      name: "workspace-kit",
      source: :project_local,
      reason: :project_local_disabled,
      explanation: "Project-local capabilities require explicit workspace trust."
    }

    assert {:ok,
            %{
              role: "assistant",
              content: content,
              metadata: %{
                surface: :operator_diagnostic,
                diagnostic_type: :capability_rejection,
                kind: :channel_reply,
                schema_version: 1
              }
            }} = OperatorResponder.build_capability_rejection(rejection)

    assert content =~ "Capability blocked"
    assert content =~ "workspace-kit was not loaded."
    assert content =~ "Project-local capabilities require explicit workspace trust."
    assert content =~ "Mark the workspace as trusted before enabling project-local capabilities."
  end

  test "build_permission_denial/1 returns an assistant reply with tool guidance" do
    event = %{
      tool_name: "bash",
      decision: :denied,
      reason: :plan_mode,
      risk: :shell_exec,
      mode: :plan
    }

    assert {:ok,
            %{
              role: "assistant",
              content: content,
              metadata: %{
                surface: :operator_diagnostic,
                diagnostic_type: :permission_denial,
                kind: :channel_reply,
                schema_version: 1
              }
            }} = OperatorResponder.build_permission_denial(event)

    assert content =~ "Tool blocked"
    assert content =~ "bash was blocked in plan mode."

    assert content =~
             "Shell execution is disabled until execution mode or explicit approval is granted."

    assert content =~ "Switch to execute mode or request approval before retrying the tool."
  end

  test "build_permission_event/1 surfaces denied permission_checked events directly" do
    event = %{
      type: :permission_checked,
      tool_name: "bash",
      decision: :denied,
      reason: :plan_mode,
      mode: :plan
    }

    assert {:ok,
            %{
              role: "assistant",
              content: content,
              metadata: %{
                surface: :operator_diagnostic,
                diagnostic_type: :permission_denial,
                kind: :channel_reply,
                schema_version: 1
              }
            }} = OperatorResponder.build_permission_event(event)

    assert content =~ "Tool blocked"
    assert content =~ "bash was blocked in plan mode."
  end

  test "build_sandbox_feedback/1 returns an assistant reply with sandbox guidance" do
    event = %{
      type: :sandbox_feedback,
      result: :blocked,
      operation: :workspace_write,
      detail: "Writes outside the allowed workspace are blocked."
    }

    assert {:ok,
            %{
              role: "assistant",
              content: content,
              metadata: %{
                surface: :operator_diagnostic,
                diagnostic_type: :sandbox_feedback,
                kind: :channel_reply,
                schema_version: 1
              }
            }} = OperatorResponder.build_sandbox_feedback(event)

    assert content =~ "Sandbox blocked"
    assert content =~ "workspace_write was blocked by the sandbox."
    assert content =~ "Adjust the sandbox policy or retry within the allowed workspace."
  end
end
