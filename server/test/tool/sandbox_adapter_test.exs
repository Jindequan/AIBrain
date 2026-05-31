defmodule AIBrain.Tool.SandboxAdapterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.SandboxAdapter

  test "feedback_event/2 builds sandbox feedback from tuple-form blocked results" do
    assert %{
             type: :sandbox_feedback,
             tool_use_id: "t1",
             operation: :workspace_write,
             result: :blocked,
             detail: "Writes outside the allowed workspace are blocked."
           } =
             SandboxAdapter.feedback_event(
               "t1",
               {:error,
                {:sandbox_blocked, :workspace_write,
                 "Writes outside the allowed workspace are blocked."}}
             )
  end

  test "feedback_event/2 returns nil for non-sandbox results" do
    assert SandboxAdapter.feedback_event("t1", {:ok, "done"}) == nil
    assert SandboxAdapter.feedback_event("t1", {:error, "plain error"}) == nil
  end

  test "tool_result_content/1 renders sandbox-blocked errors as readable detail text" do
    assert SandboxAdapter.tool_result_content(
             {:error,
              {:sandbox_blocked, :workspace_write,
               "Writes outside the allowed workspace are blocked."}}
           ) == "Writes outside the allowed workspace are blocked."
  end
end
