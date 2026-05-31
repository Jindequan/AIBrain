defmodule AIBrain.Web.GoalTasksHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AIBrain.Repo
  alias AIBrain.Data.Goal, as: Schema
  alias AIBrain.Data.Task, as: TaskSchema
  alias AIBrain.Data.Goals
  alias AIBrain.Data.Runs
  alias AIBrain.Data.Tasks
  alias AIBrain.Web.Handlers.GoalTasksHandler

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(TaskSchema)
    Repo.delete_all(Schema)

    data_dir =
      Path.join(
        System.tmp_dir!(),
        "aibrain-goal-task-api-test-#{System.unique_integer([:positive])}"
      )

    previous_data_dir = Application.get_env(:ai_brain, :data_dir)
    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      if previous_data_dir do
        Application.put_env(:ai_brain, :data_dir, previous_data_dir)
      else
        Application.delete_env(:ai_brain, :data_dir)
      end

      File.rm_rf(data_dir)
    end)

    {:ok, goal} = Goals.create(%{title: "Test Goal"})
    %{goal: goal}
  end

  describe "handle_list/2" do
    test "returns empty list", %{goal: goal} do
      conn = conn(:get, "/api/v1/goals/#{goal.id}/tasks")
      conn = GoalTasksHandler.handle_list(conn, %{"goal_id" => goal.id})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["tasks"] == []
    end

    test "returns tasks for a goal", %{goal: goal} do
      {:ok, _t1} = Tasks.create_task(%{goal_id: goal.id, title: "Task 1"})
      {:ok, _t2} = Tasks.create_task(%{goal_id: goal.id, title: "Task 2"})

      conn = conn(:get, "/api/v1/goals/#{goal.id}/tasks")
      conn = GoalTasksHandler.handle_list(conn, %{"goal_id" => goal.id})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["tasks"]) == 2
    end
  end

  describe "handle_get/2" do
    test "returns a single task", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{goal_id: goal.id, title: "Test Task"})

      conn = conn(:get, "/api/v1/tasks/#{task.id}")
      conn = GoalTasksHandler.handle_get(conn, task.id)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Test Task"
      assert body["id"] == task.id
    end

    test "returns 404 for missing task" do
      conn = conn(:get, "/api/v1/tasks/nonexistent")
      conn = GoalTasksHandler.handle_get(conn, "nonexistent")
      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Task not found"
    end
  end

  describe "handle_create/2" do
    test "creates a task with valid attrs", %{goal: goal} do
      conn = conn(:post, "/api/v1/goals/#{goal.id}/tasks")

      conn =
        GoalTasksHandler.handle_create(conn, %{
          "goal_id" => goal.id,
          "title" => "New Task"
        })

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "New Task"
      assert body["goal_id"] == goal.id
    end

    test "returns 422 for invalid attrs" do
      conn = conn(:post, "/api/v1/goals/nonexistent/tasks")
      conn = GoalTasksHandler.handle_create(conn, %{})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Validation failed"
      assert body["code"] == "validation_failed"
      assert is_map(body["errors"])
      refute conn.resp_body =~ "{:"
    end
  end

  describe "handle_update/3" do
    test "updates a task", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{goal_id: goal.id, title: "Original"})

      conn = conn(:put, "/api/v1/tasks/#{task.id}")
      conn = GoalTasksHandler.handle_update(conn, task.id, %{"title" => "Updated"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Updated"
    end

    test "does not allow API callers to rewrite run or goal ownership", %{goal: goal} do
      {:ok, other_goal} = Goals.create(%{title: "Other Goal"})

      {:ok, task} =
        Tasks.create_task(%{
          goal_id: goal.id,
          title: "Original",
          run_id: "run-original"
        })

      conn = conn(:put, "/api/v1/tasks/#{task.id}")

      conn =
        GoalTasksHandler.handle_update(conn, task.id, %{
          "title" => "Updated",
          "run_id" => "run-hijacked",
          "goal_id" => other_goal.id
        })

      assert conn.status == 200

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.title == "Updated"
      assert updated.run_id == "run-original"
      assert updated.goal_id == goal.id
    end

    test "stores output updates on disk instead of keeping full text in task row", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{goal_id: goal.id, title: "Original"})
      output = String.duplicate("large api output ", 200)

      conn = conn(:put, "/api/v1/tasks/#{task.id}")

      conn =
        GoalTasksHandler.handle_update(conn, task.id, %{
          "status" => "completed",
          "output" => output
        })

      assert conn.status == 200

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.status == "completed"
      assert updated.output != output
      assert File.read!(updated.metadata["output_path"]) == output
    end

    test "returns 404 for missing task" do
      conn = conn(:put, "/api/v1/tasks/nonexistent")
      conn = GoalTasksHandler.handle_update(conn, "nonexistent", %{"title" => "Updated"})
      assert conn.status == 404
    end
  end

  describe "handle_delete/2" do
    test "deletes a task", %{goal: goal} do
      {:ok, task} = Tasks.create_task(%{goal_id: goal.id, title: "To Delete"})

      conn = conn(:delete, "/api/v1/tasks/#{task.id}")
      conn = GoalTasksHandler.handle_delete(conn, task.id)
      assert conn.status == 200

      assert {:error, :not_found} = Tasks.get_task(task.id)
    end

    test "cancels linked run before deleting running task", %{goal: goal} do
      {:ok, run} =
        Runs.create_run(%{
          source_type: "task",
          source_id: "task-to-delete",
          status: "running",
          phase: "executing",
          objective: "delete task"
        })

      {:ok, task} =
        Tasks.create_task(%{
          goal_id: goal.id,
          title: "To Delete",
          status: "running",
          run_id: run.id
        })

      conn = conn(:delete, "/api/v1/tasks/#{task.id}")
      conn = GoalTasksHandler.handle_delete(conn, task.id)
      assert conn.status == 200

      assert {:error, :not_found} = Tasks.get_task(task.id)
      assert {:ok, cancelled} = Runs.get_run(run.id)
      assert cancelled.status == "cancelled"
    end

    test "returns 404 for missing task" do
      conn = conn(:delete, "/api/v1/tasks/nonexistent")
      conn = GoalTasksHandler.handle_delete(conn, "nonexistent")
      assert conn.status == 404
    end
  end
end
