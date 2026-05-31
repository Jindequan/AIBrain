defmodule AIBrain.AgentRuntime.GoalDaemonTest do
  use AIBrain.DataCase, async: false

  alias AIBrain.AgentRuntime.GoalDaemon
  alias AIBrain.Data.{EpisodicMemories, Goals, RunContextRefs, Runs, Tasks}

  test "scan starts a goal_tick run for autonomous active goals" do
    parent = self()

    {:ok, goal} =
      Goals.create(%{
        title: "Run a creator account",
        description: "Grow the account with weekly content experiments",
        metadata: %{
          "autonomous" => true,
          "autonomy_level" => 2,
          "strategy" => %{
            "current_assessment" => "Posting is inconsistent.",
            "next_actions" => ["Review metrics"],
            "blockers" => [],
            "needs_owner_input" => false,
            "next_focus" => "Cadence"
          }
        }
      })

    {:ok, _task} =
      Tasks.create_task(%{
        goal_id: goal.id,
        title: "Draft content pillars",
        status: "completed"
      })

    {:ok, _memory} =
      EpisodicMemories.create(%{
        goal_id: goal.id,
        narrative: "Previous review showed that weekly cadence beats sporadic posting.",
        lessons: ["Keep weekly cadence"],
        importance_score: 0.8
      })

    runner = fn attrs, opts ->
      send(parent, {:goal_tick, attrs, opts})
      {:ok, "run-goal-1"}
    end

    {:ok, pid} =
      start_supervised({GoalDaemon, name: daemon_name(), scan_interval: 3600, runner: runner})

    assert {:ok, ["run-goal-1"]} = GoalDaemon.scan_now(pid)

    assert_receive {:goal_tick, attrs, opts}
    assert attrs.source_type == "goal"
    assert attrs.source_id == goal.id
    assert attrs.goal_id == goal.id
    assert attrs.mode == "goal_tick"
    assert attrs.autonomy_level == 2
    assert attrs.metadata["entrypoint"] == "goal.daemon"
    assert opts[:permission_mode] == :approval_required
    assert opts[:autonomy_allowed_tools] == ["goal_task"]
    assert opts[:max_turns] == 80
    assert String.contains?(attrs.objective, "Run a creator account")
    assert String.contains?(attrs.objective, "Draft content pillars")
    assert String.contains?(attrs.objective, "Posting is inconsistent")
    assert String.contains?(attrs.objective, "weekly cadence beats sporadic posting")
    assert String.contains?(attrs.objective, "record_goal_strategy")

    assert {:ok, updated_goal} = Goals.get(goal.id)
    assert updated_goal.metadata["last_goal_daemon_run_id"] == "run-goal-1"
    assert updated_goal.metadata["next_review_after"]
    refute Map.has_key?(updated_goal.metadata, "last_review_error")
  end

  test "scan ignores active goals without autonomy metadata" do
    parent = self()
    {:ok, _goal} = Goals.create(%{title: "Manual only goal"})

    runner = fn attrs, opts ->
      send(parent, {:unexpected_goal_tick, attrs, opts})
      {:ok, "run-unexpected"}
    end

    {:ok, pid} =
      start_supervised({GoalDaemon, name: daemon_name(), scan_interval: 3600, runner: runner})

    assert {:ok, []} = GoalDaemon.scan_now(pid)
    refute_receive {:unexpected_goal_tick, _attrs, _opts}, 100
  end

  test "scan skips goals that already have an active goal run" do
    parent = self()

    {:ok, goal} =
      Goals.create(%{
        title: "Health management",
        metadata: %{"autonomous" => true}
      })

    {:ok, run} =
      Runs.create_run(%{
        source_type: "goal",
        source_id: goal.id,
        status: "running",
        mode: "goal_tick"
      })

    :ok =
      RunContextRefs.create_many(run.id, [%{ref_type: "goal", ref_id: goal.id, role: "parent"}])

    runner = fn attrs, opts ->
      send(parent, {:unexpected_goal_tick, attrs, opts})
      {:ok, "run-unexpected"}
    end

    {:ok, pid} =
      start_supervised({GoalDaemon, name: daemon_name(), scan_interval: 3600, runner: runner})

    assert {:ok, []} = GoalDaemon.scan_now(pid)
    refute_receive {:unexpected_goal_tick, _attrs, _opts}, 100
  end

  test "scan uses goal metadata next_review_after as cooldown even without a run row" do
    parent = self()

    {:ok, _goal} =
      Goals.create(%{
        title: "Autonomous with cooldown",
        metadata: %{
          "autonomous" => true,
          "next_review_after" =>
            DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
        }
      })

    runner = fn attrs, opts ->
      send(parent, {:unexpected_goal_tick, attrs, opts})
      {:ok, "run-unexpected"}
    end

    {:ok, pid} =
      start_supervised({GoalDaemon, name: daemon_name(), scan_interval: 3600, runner: runner})

    assert {:ok, []} = GoalDaemon.scan_now(pid)
    refute_receive {:unexpected_goal_tick, _attrs, _opts}, 100
  end

  test "failed review records error and future cooldown" do
    {:ok, goal} =
      Goals.create(%{
        title: "Autonomous failure",
        metadata: %{"autonomous" => true, "goal_daemon_cooldown_seconds" => 1800}
      })

    runner = fn _attrs, _opts -> {:error, :provider_unavailable} end

    {:ok, pid} =
      start_supervised({GoalDaemon, name: daemon_name(), scan_interval: 3600, runner: runner})

    assert {:ok, []} = GoalDaemon.scan_now(pid)

    assert {:ok, updated_goal} = Goals.get(goal.id)
    assert updated_goal.metadata["last_review_error"] == ":provider_unavailable"
    assert updated_goal.metadata["last_review_failed_at"]
    assert updated_goal.metadata["next_review_after"]
  end

  defp daemon_name do
    :"goal_daemon_test_#{System.unique_integer([:positive])}"
  end
end
