defmodule AIBrain.Permissions.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias AIBrain.Permissions.Diagnostics

  test "summarize/1 builds approval and denial counts from permission events" do
    events = [
      %{
        type: :permission_checked,
        tool_name: "write_echo",
        decision: :denied,
        reason: :plan_mode,
        mode: :plan
      },
      %{
        type: :permission_checked,
        tool_name: "write_echo",
        decision: :approved,
        reason: :approval_granted,
        mode: :approval_required
      },
      %{type: :text_delta, text: "ignored"}
    ]

    assert %{
             counts: %{approved: 1, denied: 1},
             denials: [
               %{
                 tool_name: "write_echo",
                 reason: :plan_mode,
                 mode: :plan,
                 severity: :warning
               }
             ]
           } = Diagnostics.summarize(events)
  end
end
