defmodule AIBrain.Engine.LoopTest do
  use ExUnit.Case, async: true

  alias AIBrain.Engine.Loop

  test "prepare_messages/4 applies context budget" do
    msgs = for i <- 1..100, do: %{role: "user", content: "message #{i}"}
    result = Loop.prepare_messages(msgs, "system prompt", nil, max_context_tokens: 100)
    assert is_list(result)
    assert length(result) < length(msgs)
  end

  test "prepare_messages/4 returns messages unchanged when under budget" do
    msgs = [%{role: "user", content: "hi"}]
    assert Loop.prepare_messages(msgs, "", nil, []) == msgs
  end

  test "check_limits/4 returns :continue when within limits" do
    assert Loop.check_limits(0, 200, DateTime.utc_now(), 1800) == :continue
  end

  test "check_limits/4 returns {:stop, reason} when max_turns exceeded" do
    assert Loop.check_limits(200, 200, DateTime.utc_now(), 1800) == {:stop, :max_turns_exceeded}
  end

  test "check_limits/4 returns {:stop, reason} when wall time exceeded" do
    started_at = DateTime.add(DateTime.utc_now(), -2000, :second)
    assert Loop.check_limits(0, 200, started_at, 1800) == {:stop, :wall_time_exceeded}
  end
end
