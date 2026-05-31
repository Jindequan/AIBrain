defmodule AIBrain.Task.DispatcherTest do
  use ExUnit.Case, async: false

  alias AIBrain.Task.Dispatcher
  alias AIBrain.Data.{Tasks, Goals}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AIBrain.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AIBrain.Repo, {:shared, self()})

    data_dir =
      Path.join(
        System.tmp_dir!(),
        "aibrain-dispatcher-test-#{System.unique_integer([:positive])}"
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

  describe "notify_pending/1" do
    test "dispatches pending tasks with mock runner", %{goal: goal} do
      test_pid = self()

      {:ok, task} =
        Tasks.create_task(%{
          title: "Run me",
          description: "Do something",
          goal_id: goal.id,
          status: "pending"
        })

      mock_runner = fn assistant, _input, opts ->
        send(test_pid, {:runner_called, assistant, opts[:metadata]})
        {:ok, "run-#{System.unique_integer([:positive])}"}
      end

      {:ok, dispatcher} =
        Dispatcher.start_link(
          name: nil,
          runner: mock_runner,
          poll_interval: 60_000
        )

      Dispatcher.dispatch_now(dispatcher)

      # Drain all runner_called messages and find the one for our task
      task_id = task.id
      assert_receive {:runner_called, "default", %{task_id: ^task_id}}, 1000

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.status == "running"
      assert is_binary(updated.run_id)
    end

    test "preserves schedule context for scheduled tasks", %{goal: goal} do
      test_pid = self()

      {:ok, task} =
        Tasks.create_task(%{
          title: "Run from schedule",
          goal_id: goal.id,
          status: "pending",
          metadata: %{"schedule_id" => "schedule-123"}
        })

      mock_runner = fn assistant, _input, opts ->
        send(test_pid, {:runner_called, assistant, opts[:metadata], opts[:context]})
        {:ok, "run-#{System.unique_integer([:positive])}"}
      end

      {:ok, dispatcher} =
        Dispatcher.start_link(
          name: nil,
          runner: mock_runner,
          poll_interval: 60_000
        )

      Dispatcher.dispatch_now(dispatcher)

      task_id = task.id

      assert_receive {:runner_called, "default", metadata, context}, 1000
      assert metadata.task_id == task_id
      assert metadata.goal_id == goal.id
      assert metadata.schedule_id == "schedule-123"
      assert context.schedule_id == "schedule-123"
    end

    test "preserves workspace and autonomy context for task runs", %{goal: goal} do
      test_pid = self()

      {:ok, task} =
        Tasks.create_task(%{
          title: "Run with local context",
          goal_id: goal.id,
          status: "pending",
          metadata: %{
            "workspace_path" => "/tmp/aibrain-project",
            "autonomy_level" => 2,
            "max_turns" => 12,
            "max_wall_time" => 300
          }
        })

      mock_runner = fn _assistant, _input, opts ->
        send(test_pid, {:runner_called, opts[:metadata], opts[:context]})
        {:ok, "run-#{System.unique_integer([:positive])}"}
      end

      {:ok, dispatcher} =
        Dispatcher.start_link(
          name: nil,
          runner: mock_runner,
          poll_interval: 60_000
        )

      Dispatcher.dispatch_now(dispatcher)

      task_id = task.id
      assert_receive {:runner_called, metadata, context}, 1000
      assert metadata.task_id == task_id
      assert metadata.workspace_path == "/tmp/aibrain-project"
      assert metadata.autonomy_level == 2
      assert metadata.max_turns == 12
      assert metadata.max_wall_time == 300
      assert context.workspace_path == "/tmp/aibrain-project"
      assert context.autonomy_level == 2
    end

    test "marks task failed when run creation fails", %{goal: goal} do
      {:ok, task} =
        Tasks.create_task(%{
          title: "Cannot start",
          goal_id: goal.id,
          status: "pending"
        })

      {:ok, dispatcher} =
        Dispatcher.start_link(
          name: nil,
          runner: fn _, _, _ -> {:error, :runner_unavailable} end,
          poll_interval: 60_000
        )

      Dispatcher.dispatch_now(dispatcher)

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.status == "failed"
      assert updated.output =~ "runner_unavailable"
    end

    test "default runner starts task runs in approval mode" do
      test_pid = self()

      attrs_runner = fn attrs, opts ->
        send(test_pid, {:run_attrs, attrs, opts})
        {:ok, "run-approval"}
      end

      {:ok, task} = Tasks.create_task(%{title: "Needs tools", status: "pending"})

      assert {:ok, "run-approval"} =
               Dispatcher.start_task_run(
                 "do the work",
                 [
                   assistant_name: "default",
                   metadata: %{task_id: task.id},
                   context: %{task_id: task.id}
                 ],
                 attrs_runner
               )

      assert_receive {:run_attrs, attrs, opts}, 1000
      assert attrs.source_type == "task"
      assert attrs.task_id == task.id
      assert attrs.opts[:permission_mode] == :approval_required
      assert opts[:permission_mode] == :approval_required
      assert opts[:autonomy_allowed_tools] == ["goal_task"]
    end
  end

  describe "run completion" do
    test "marks task completed on successful run", %{goal: goal} do
      run_id = "run-complete-#{System.unique_integer([:positive])}"

      {:ok, task} =
        Tasks.create_task(%{
          title: "Complete me",
          goal_id: goal.id,
          status: "running",
          run_id: run_id
        })

      {:ok, dispatcher} = Dispatcher.start_link(name: nil, runner: fn _, _, _ -> {:ok, "x"} end)
      send(dispatcher, {:run_complete, run_id, {:ok, "great result", []}})

      Process.sleep(100)

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.status == "completed"
      assert updated.output == "great result"
    end

    test "marks task failed on error run", %{goal: goal} do
      run_id = "run-fail-#{System.unique_integer([:positive])}"

      {:ok, task} =
        Tasks.create_task(%{
          title: "Fail me",
          goal_id: goal.id,
          status: "running",
          run_id: run_id
        })

      {:ok, dispatcher} = Dispatcher.start_link(name: nil, runner: fn _, _, _ -> {:ok, "x"} end)
      send(dispatcher, {:run_complete, run_id, {:error, :max_turns_exceeded}})

      Process.sleep(100)

      {:ok, updated} = Tasks.get_task(task.id)
      assert updated.status == "failed"
    end
  end
end
