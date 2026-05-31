defmodule AIBrain.LLM.ClientExpandTest do
  use ExUnit.Case, async: true

  alias AIBrain.LLM.Adapters.Protocol.OpenAI

  test "expand_consolidated_messages is idempotent" do
    # Simulates a consolidated assistant message (tool result embedded in tool_use block,
    # no following tool message — this happens when session is restored from storage)
    tool_block = %{type: "tool_use", id: "t1", name: "bash", input: %{}, output: "hello"}
    msg = %{role: "assistant", content: [%{type: "text", text: "Done."}, tool_block]}
    next_msg = %{role: "user", content: "continue"}
    messages = [msg, next_msg]

    once = OpenAI.expand_consolidated_messages(messages)
    twice = OpenAI.expand_consolidated_messages(once)

    # Expanding once and twice yields the same result (idempotent)
    assert once == twice
  end
end
