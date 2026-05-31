defmodule AIBrain.Planning.PlannerTest do
  use ExUnit.Case

  alias AIBrain.Planning.Planner

  test "module exists and responds to plan" do
    assert Code.ensure_loaded?(Planner)
    assert function_exported?(Planner, :plan, 1)
  end
end
