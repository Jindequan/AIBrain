defmodule AIBrain.Planning.ExecutorTest do
  use AIBrain.DataCase

  alias AIBrain.Planning.Executor
  alias AIBrain.Data.Goals

  describe "compute_waves/1" do
    test "single task with no dependencies returns one wave" do
      task = %{id: "t1", depends_on: [], title: "A"}
      assert Executor.compute_waves([task]) == [[task]]
    end

    test "two sequential tasks produce two waves" do
      t1 = %{id: "t1", depends_on: [], title: "A"}
      t2 = %{id: "t2", depends_on: ["t1"], title: "B"}
      waves = Executor.compute_waves([t1, t2])
      assert length(waves) == 2
      assert Enum.map(hd(waves), & &1.id) == ["t1"]
      assert Enum.map(List.last(waves), & &1.id) == ["t2"]
    end

    test "parallel tasks are in same wave" do
      t1 = %{id: "t1", depends_on: [], title: "A"}
      t2 = %{id: "t2", depends_on: [], title: "B"}
      waves = Executor.compute_waves([t1, t2])
      assert length(waves) == 1
      assert length(hd(waves)) == 2
    end

    test "diamond dependency resolves to three waves" do
      root = %{id: "root", depends_on: [], title: "Root"}
      left = %{id: "left", depends_on: ["root"], title: "Left"}
      right = %{id: "right", depends_on: ["root"], title: "Right"}
      final = %{id: "final", depends_on: ["left", "right"], title: "Final"}

      waves = Executor.compute_waves([root, left, right, final])
      assert length(waves) == 3
      assert Enum.map(hd(waves), & &1.id) == ["root"]
      assert length(Enum.at(waves, 1)) == 2
      assert Enum.map(List.last(waves), & &1.id) == ["final"]
    end

    test "empty tasks list returns empty waves" do
      assert Executor.compute_waves([]) == []
    end
  end

  describe "execute/2" do
    setup do
      {:ok, goal} = Goals.create(%{title: "Exec Goal", description: "Test"})
      %{goal: goal}
    end

    test "returns error for non-existent goal" do
      assert Executor.execute("nonexistent") == {:error, :goal_not_found}
    end

    test "executes goal with no tasks returns summary", %{goal: goal} do
      {:ok, result} = Executor.execute(goal.id)
      assert result.goal.id == goal.id
      assert result.tasks == []
    end
  end
end
