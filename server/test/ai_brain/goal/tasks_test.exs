defmodule AIBrain.Goal.TasksTest do
  use AIBrain.DataCase
  alias AIBrain.Data.Tasks
  alias AIBrain.Data.Goals

  describe "list_tasks/1" do
    test "returns tasks for a goal" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})
      {:ok, task1} = Tasks.create_task(%{goal_id: goal.id, title: "Task 1"})
      {:ok, task2} = Tasks.create_task(%{goal_id: goal.id, title: "Task 2"})
      {:ok, _other_task} = Tasks.create_task(%{title: "Other task"})

      tasks = Tasks.list_tasks(goal.id)

      assert length(tasks) == 2
      assert Enum.any?(tasks, fn t -> t.id == task1.id end)
      assert Enum.any?(tasks, fn t -> t.id == task2.id end)
    end

    test "returns empty list for goal with no tasks" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})

      tasks = Tasks.list_tasks(goal.id)

      assert tasks == []
    end
  end

  describe "get_task!/1" do
    test "returns the task when it exists" do
      {:ok, task} = Tasks.create_task(%{title: "Test Task"})

      found_task = Tasks.get_task!(task.id)

      assert found_task.id == task.id
      assert found_task.title == "Test Task"
    end

    test "raises Ecto.NoResultsError when task doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_task/1" do
    test "returns {:ok, task} when it exists" do
      {:ok, task} = Tasks.create_task(%{title: "Test Task"})

      assert {:ok, found_task} = Tasks.get_task(task.id)
      assert found_task.id == task.id
      assert found_task.title == "Test Task"
    end

    test "returns {:error, :not_found} when task doesn't exist" do
      assert {:error, :not_found} = Tasks.get_task(Ecto.UUID.generate())
    end
  end

  describe "create_task/1" do
    test "creates a task with valid attrs" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})

      attrs = %{
        goal_id: goal.id,
        title: "New Task",
        description: "Task description",
        status: "pending"
      }

      assert {:ok, task} = Tasks.create_task(attrs)
      assert task.title == "New Task"
      assert task.description == "Task description"
      assert task.status == "pending"
      assert task.goal_id == goal.id
    end

    test "returns error changeset with invalid attrs" do
      attrs = %{
        title: nil
      }

      assert {:error, %Ecto.Changeset{}} = Tasks.create_task(attrs)
    end

    test "returns error changeset when goal doesn't exist" do
      attrs = %{
        goal_id: Ecto.UUID.generate(),
        title: "New Task"
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Tasks.create_task(attrs)
      assert {"does not exist", []} == changeset.errors[:goal_id]
    end
  end

  describe "update_task/2" do
    test "updates the task with valid attrs" do
      {:ok, task} = Tasks.create_task(%{title: "Original Title"})
      attrs = %{title: "Updated Title"}

      assert {:ok, updated_task} = Tasks.update_task(task, attrs)
      assert updated_task.title == "Updated Title"
    end

    test "returns error changeset with invalid attrs" do
      {:ok, task} = Tasks.create_task(%{title: "Test"})
      attrs = %{title: nil}

      assert {:error, %Ecto.Changeset{}} = Tasks.update_task(task, attrs)
    end

    test "returns error changeset when goal_id is changed to non-existent goal" do
      {:ok, task} = Tasks.create_task(%{title: "Test"})
      attrs = %{goal_id: Ecto.UUID.generate()}

      assert {:error, %Ecto.Changeset{} = changeset} = Tasks.update_task(task, attrs)
      assert {"does not exist", []} == changeset.errors[:goal_id]
    end
  end

  describe "delete_task/1" do
    test "deletes the task" do
      {:ok, task} = Tasks.create_task(%{title: "Test"})

      assert {:ok, deleted_task} = Tasks.delete_task(task)
      assert deleted_task.id == task.id

      assert {:error, :not_found} = Tasks.get_task(task.id)
    end

    test "returns error when task doesn't exist" do
      # Create a struct that looks like it exists but doesn't
      fake_task = struct(AIBrain.Data.Task, id: Ecto.UUID.generate())

      assert_raise Ecto.StaleEntryError, fn ->
        Tasks.delete_task(fake_task)
      end
    end
  end

  describe "change_task/2" do
    test "returns a task changeset" do
      {:ok, task} = Tasks.create_task(%{title: "Test"})

      assert %Ecto.Changeset{} = Tasks.change_task(task)
      assert %Ecto.Changeset{} = Tasks.change_task(task, %{title: "New Title"})
    end
  end

  describe "list_tasks_by_status/2" do
    test "returns tasks with specified status" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})
      Tasks.create_task(%{goal_id: goal.id, title: "Pending Task", status: "pending"})
      Tasks.create_task(%{goal_id: goal.id, title: "In Progress Task", status: "in_progress"})
      Tasks.create_task(%{goal_id: goal.id, title: "Completed Task", status: "completed"})

      pending_tasks = Tasks.list_tasks_by_status(goal.id, "pending")
      in_progress_tasks = Tasks.list_tasks_by_status(goal.id, "in_progress")
      completed_tasks = Tasks.list_tasks_by_status(goal.id, "completed")

      assert length(pending_tasks) == 1
      assert length(in_progress_tasks) == 1
      assert length(completed_tasks) == 1
      assert hd(pending_tasks).title == "Pending Task"
      assert hd(in_progress_tasks).title == "In Progress Task"
      assert hd(completed_tasks).title == "Completed Task"
    end

    test "returns empty list when no tasks with specified status" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})
      Tasks.create_task(%{goal_id: goal.id, status: "pending"})

      tasks = Tasks.list_tasks_by_status(goal.id, "completed")

      assert tasks == []
    end
  end

  describe "count_tasks_by_status/1" do
    test "returns count of tasks grouped by status" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})
      Tasks.create_task(%{goal_id: goal.id, title: "Task 1", status: "pending"})
      Tasks.create_task(%{goal_id: goal.id, title: "Task 2", status: "pending"})
      Tasks.create_task(%{goal_id: goal.id, title: "Task 3", status: "in_progress"})
      Tasks.create_task(%{goal_id: goal.id, title: "Task 4", status: "completed"})

      counts = Tasks.count_tasks_by_status(goal.id)

      assert counts["pending"] == 2
      assert counts["in_progress"] == 1
      assert counts["completed"] == 1
    end

    test "returns zero counts for goal with no tasks" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})

      counts = Tasks.count_tasks_by_status(goal.id)

      assert counts["pending"] == 0
      assert counts["in_progress"] == 0
      assert counts["completed"] == 0
    end
  end

  describe "update_task_status/2" do
    test "updates task status" do
      {:ok, task} = Tasks.create_task(%{title: "Test", status: "pending"})

      assert {:ok, updated_task} = Tasks.update_task_status(task, "in_progress")
      assert updated_task.status == "in_progress"
    end

    test "returns error changeset with invalid status" do
      {:ok, task} = Tasks.create_task(%{title: "Test"})

      assert {:error, %Ecto.Changeset{}} = Tasks.update_task_status(task, "invalid_status")
    end
  end

  describe "reorder_tasks/2" do
    test "returns :ok for valid goal" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})

      assert :ok = Tasks.reorder_tasks(goal.id, [])
    end

    test "returns error when goal doesn't exist" do
      assert {:error, :not_found} = Tasks.reorder_tasks(Ecto.UUID.generate(), [])
    end
  end
end
