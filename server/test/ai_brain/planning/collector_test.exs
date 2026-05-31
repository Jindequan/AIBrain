defmodule AIBrain.Planning.CollectorTest do
  use AIBrain.DataCase

  alias AIBrain.Planning.Collector
  alias AIBrain.Data.{Goals, Tasks}

  describe "collect/1" do
    test "returns error for non-existent goal" do
      assert Collector.collect("nonexistent") == {:error, :not_found}
    end

    test "returns goal with no tasks" do
      {:ok, goal} = Goals.create(%{title: "Empty Goal", description: "No tasks"})
      {:ok, report} = Collector.collect(goal.id)
      assert report.goal.title == "Empty Goal"
      assert report.tasks == []
      assert report.stats.total == 0
    end

    test "reports task statuses correctly" do
      {:ok, goal} = Goals.create(%{title: "Test Goal", description: "test"})

      {:ok, t1} =
        Tasks.create_task(%{goal_id: goal.id, title: "Done", status: "completed", output: "ok"})

      {:ok, _t2} = Tasks.create_task(%{goal_id: goal.id, title: "Fail", status: "failed"})

      {:ok, report} = Collector.collect(goal.id)
      assert report.stats.total == 2
      assert report.stats.completed == 1
      assert report.stats.failed == 1

      done_task = Enum.find(report.tasks, &(&1.id == t1.id))
      assert done_task.status == "completed"
      assert done_task.output == "ok"
    end

    test "handles mixed statuses" do
      {:ok, goal} = Goals.create(%{title: "Mixed", description: "test"})
      Tasks.create_task(%{goal_id: goal.id, title: "A", status: "completed"})
      Tasks.create_task(%{goal_id: goal.id, title: "B", status: "failed"})
      Tasks.create_task(%{goal_id: goal.id, title: "C", status: "pending"})
      Tasks.create_task(%{goal_id: goal.id, title: "D", status: "cancelled"})

      {:ok, report} = Collector.collect(goal.id)
      assert report.stats.completed == 1
      assert report.stats.failed == 1
      assert report.stats.pending == 1
      assert report.stats.cancelled == 1
      assert report.stats.total == 4
    end
  end
end
