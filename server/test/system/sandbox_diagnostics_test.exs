defmodule AIBrain.System.SandboxDiagnosticsTest do
  use ExUnit.Case, async: true

  alias AIBrain.System.SandboxDiagnostics, as: Diagnostics

  test "summarize/1 builds counts and blocked entries from sandbox events" do
    events = [
      %{
        type: :sandbox_feedback,
        tool_use_id: "s1",
        operation: :workspace_write,
        result: :blocked,
        detail: "Writes outside the allowed workspace are blocked."
      },
      %{
        type: :sandbox_feedback,
        tool_use_id: "s2",
        operation: :workspace_read,
        result: :allowed,
        detail: "allowed"
      },
      %{type: :text_delta, text: "ignored"}
    ]

    assert %{
             counts: %{allowed: 1, blocked: 1},
             blocked: [
               %{
                 tool_use_id: "s1",
                 operation: :workspace_write,
                 result: :blocked,
                 detail: "Writes outside the allowed workspace are blocked.",
                 severity: :warning
               }
             ]
           } = Diagnostics.summarize(events)
  end
end
