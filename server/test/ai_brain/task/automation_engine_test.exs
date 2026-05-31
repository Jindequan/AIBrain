defmodule AIBrain.Task.AutomationEngineTest do
  use AIBrain.DataCase

  alias AIBrain.Data.{Goals, Schedules, Runs, Tasks}
  alias AIBrain.Task.AutomationEngine

  test "due run_query schedule starts a scheduled run request" do
    parent = self()

    runner = fn attrs, opts ->
      send(parent, {:scheduled_run, attrs, opts})
      {:ok, "run-from-schedule"}
    end

    server =
      start_supervised!(
        {AutomationEngine,
         name: :"automation_engine_#{System.unique_integer([:positive])}",
         scan_interval: 3600,
         runner: runner}
      )

    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "Daily market brief",
        trigger_type: "time",
        trigger_config: %{},
        action_type: "run_query",
        action_config: %{
          "title" => "Market brief",
          "prompt" => "Summarize market news.",
          "autonomy_level" => 2
        },
        next_fire_at: DateTime.utc_now() |> DateTime.add(-60, :second)
      })

    assert {:ok, [schedule_id]} = AutomationEngine.scan_now(server)
    assert schedule_id == schedule.id

    assert_receive {:scheduled_run, attrs, opts}
    assert attrs.source_type == "schedule"
    assert attrs.source_id == schedule.id
    assert attrs.schedule_id == schedule.id
    assert attrs.goal_id == nil
    assert attrs.mode == "scheduled"
    assert attrs.autonomy_level == 2
    assert attrs.title == "Market brief"
    assert attrs.opts[:permission_mode] == :approval_required
    assert attrs.opts[:autonomy_allowed_tools] == ["goal_task"]
    assert opts[:permission_mode] == :approval_required
    assert opts[:max_turns] == 80
    assert [%{role: "user", content: "Summarize market news."}] = attrs.messages

    assert {:ok, updated} = Schedules.get_schedule(schedule.id)
    assert updated.last_fired_at
    assert updated.next_fire_at == nil
    assert updated.status == "completed"
    assert updated.last_result =~ "run-from-schedule"

    assert [] = Runs.list_runs_for_ref("schedule", schedule.id)
  end

  test "create_task schedule preserves goal and autonomy context" do
    {:ok, goal} = Goals.create(%{title: "Long goal"})

    server =
      start_supervised!(
        {AutomationEngine,
         name: :"automation_engine_#{System.unique_integer([:positive])}",
         scan_interval: 3600,
         runner: fn _, _ -> {:ok, "unused"} end}
      )

    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "Goal task tick",
        trigger_type: "time",
        action_type: "create_task",
        action_config: %{
          "title" => "Review weekly goal",
          "description" => "Check progress",
          "goal_id" => goal.id,
          "autonomy_level" => 2,
          "workspace_path" => "/tmp/aibrain-work"
        },
        next_fire_at: DateTime.utc_now() |> DateTime.add(-60, :second)
      })

    assert {:ok, [schedule_id]} = AutomationEngine.scan_now(server)
    assert schedule_id == schedule.id

    [task] = Tasks.list_tasks(goal.id)
    assert task.title == "Review weekly goal"
    assert task.goal_id == goal.id
    assert task.metadata["schedule_id"] == schedule.id
    assert task.metadata["autonomy_level"] == 2
    assert task.metadata["workspace_path"] == "/tmp/aibrain-work"

    assert {:ok, updated} = Schedules.get_schedule(schedule.id)
    assert updated.status == "completed"
    assert updated.last_result =~ task.id
  end

  test "condition schedule fires when local condition is true" do
    parent = self()

    flag_path =
      Path.join(System.tmp_dir!(), "aibrain_condition_#{System.unique_integer([:positive])}")

    File.write!(flag_path, "ready")

    runner = fn attrs, _opts ->
      send(parent, {:condition_run, attrs})
      {:ok, "condition-run"}
    end

    server =
      start_supervised!(
        {AutomationEngine,
         name: :"automation_engine_#{System.unique_integer([:positive])}",
         scan_interval: 3600,
         runner: runner}
      )

    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "When flag exists",
        trigger_type: "condition",
        trigger_config: %{"type" => "file_exists", "path" => flag_path},
        action_type: "run_query",
        action_config: %{"prompt" => "Flag is ready"}
      })

    assert {:ok, [schedule_id]} = AutomationEngine.scan_now(server)
    assert schedule_id == schedule.id
    assert_receive {:condition_run, %{source_type: "schedule", source_id: ^schedule_id}}

    File.rm(flag_path)
  end

  test "condition schedule skips when local condition is false" do
    missing_path =
      Path.join(System.tmp_dir!(), "aibrain_missing_#{System.unique_integer([:positive])}")

    server =
      start_supervised!(
        {AutomationEngine,
         name: :"automation_engine_#{System.unique_integer([:positive])}",
         scan_interval: 3600,
         runner: fn _, _ -> flunk("runner should not be called") end}
      )

    {:ok, _schedule} =
      Schedules.create_schedule(%{
        name: "When missing flag exists",
        trigger_type: "condition",
        trigger_config: %{"type" => "file_exists", "path" => missing_path},
        action_type: "run_query",
        action_config: %{"prompt" => "Should not run"}
      })

    assert {:ok, []} = AutomationEngine.scan_now(server)
  end
end
