defmodule AIBrain.Engine.LoopToolOutputTest do
  use ExUnit.Case, async: true

  alias AIBrain.Engine.Loop

  test "tool output larger than 10KB is truncated with marker" do
    large_output = String.duplicate("x", 15_000)
    result = Loop.truncate_tool_output(large_output, "test_tool")
    assert byte_size(result) <= 10_200
    assert String.contains?(result, "[truncated")
  end

  test "tool output under 10KB is stored intact" do
    small_output = String.duplicate("x", 5_000)
    result = Loop.truncate_tool_output(small_output, "test_tool")
    assert result == small_output
  end

  test "tool output exactly at limit is stored intact" do
    exact_output = String.duplicate("x", 10_000)
    result = Loop.truncate_tool_output(exact_output, "test_tool")
    assert result == exact_output
  end
end
