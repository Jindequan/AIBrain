defmodule AIBrain.Data.TasksTest do
  use AIBrain.DataCase

  alias AIBrain.Data.{Tasks, Goals}

  setup do
    {:ok, goal} = Goals.create(%{title: "Test Goal"})
    %{goal: goal}
  end

  describe "list_by_ids/1" do
    test "returns tasks matching the given IDs", %{goal: goal} do
      {:ok, t1} = Tasks.create_task(%{title: "A", goal_id: goal.id})
      {:ok, _t2} = Tasks.create_task(%{title: "B", goal_id: goal.id})
      {:ok, t3} = Tasks.create_task(%{title: "C", goal_id: goal.id})
      results = Tasks.list_by_ids([t1.id, t3.id])
      assert length(results) == 2
      assert Enum.map(results, & &1.id) |> Enum.sort() == [t1.id, t3.id] |> Enum.sort()
    end
  end

  describe "list_incomplete_dependencies/1" do
    test "returns incomplete dep tasks", %{goal: goal} do
      {:ok, dep} = Tasks.create_task(%{title: "Dependency", goal_id: goal.id})
      {:ok, task} = Tasks.create_task(%{title: "Main", goal_id: goal.id, depends_on: [dep.id]})
      incomplete = Tasks.list_incomplete_dependencies(task)
      assert length(incomplete) == 1
      assert hd(incomplete).id == dep.id
    end

    test "returns empty when deps are completed", %{goal: goal} do
      {:ok, dep} = Tasks.create_task(%{title: "Done Dep", goal_id: goal.id})
      Tasks.update_task(dep, %{status: "completed"})
      {:ok, task} = Tasks.create_task(%{title: "Main", goal_id: goal.id, depends_on: [dep.id]})
      assert Tasks.list_incomplete_dependencies(task) == []
    end

    test "returns empty when no depends_on", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{title: "No Deps", goal_id: goal.id})
      assert Tasks.list_incomplete_dependencies(task) == []
    end
  end

  describe "list_pending_dispatchable/0" do
    test "returns pending tasks with satisfied deps", %{goal: goal} do
      {:ok, task} =
        Tasks.create_task(%{
          title: "Ready",
          goal_id: goal.id,
          status: "pending"
        })

      result = Tasks.list_pending_dispatchable()
      assert Enum.any?(result, &(&1.id == task.id))
    end

    test "excludes tasks with incomplete dependencies", %{goal: goal} do
      {:ok, dep} = Tasks.create_task(%{title: "Dep", goal_id: goal.id})

      {:ok, task} =
        Tasks.create_task(%{
          title: "Blocked",
          goal_id: goal.id,
          status: "pending",
          depends_on: [dep.id]
        })

      result = Tasks.list_pending_dispatchable()
      refute Enum.any?(result, &(&1.id == task.id))
    end

    test "includes pending tasks without assigned_agent", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{title: "No Agent", goal_id: goal.id, status: "pending"})
      result = Tasks.list_pending_dispatchable()
      assert Enum.any?(result, &(&1.id == task.id))
    end
  end

  describe "get_by_run_id/1" do
    test "returns task matching run_id", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{title: "T", goal_id: goal.id})
      {:ok, updated} = Tasks.update_task(task, %{run_id: "run-abc"})
      assert {:ok, found} = Tasks.get_by_run_id("run-abc")
      assert found.id == updated.id
    end

    test "returns not_found for unknown run_id" do
      assert {:error, :not_found} = Tasks.get_by_run_id("run-nonexistent")
    end
  end

  describe "update_task_result/3" do
    test "stores full output on disk and keeps only a summary in the task row", %{goal: goal} do
      data_dir =
        Path.join(System.tmp_dir!(), "aibrain-task-output-#{System.unique_integer([:positive])}")

      previous = Application.get_env(:ai_brain, :data_dir)
      Application.put_env(:ai_brain, :data_dir, data_dir)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ai_brain, :data_dir, previous),
          else: Application.delete_env(:ai_brain, :data_dir)

        File.rm_rf(data_dir)
      end)

      {:ok, task} = Tasks.create_task(%{title: "Large output", goal_id: goal.id})
      output = String.duplicate("long task output ", 200)

      assert {:ok, updated} = Tasks.update_task_result(task, "completed", output)
      assert updated.status == "completed"
      assert byte_size(updated.output) <= 1_000
      assert updated.output != output
      assert is_binary(updated.metadata["output_path"])
      assert updated.metadata["output_truncated"] == true
      assert File.read!(updated.metadata["output_path"]) == output
    end
  end
end
