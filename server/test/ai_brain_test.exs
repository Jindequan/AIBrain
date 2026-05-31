defmodule AiBrainTest do
  use ExUnit.Case
  doctest AiBrain

  test "exposes the unified runtime entrypoint" do
    assert function_exported?(AiBrain, :run, 2)
  end
end
