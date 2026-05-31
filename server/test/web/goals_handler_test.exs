defmodule AIBrain.Web.GoalsHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AIBrain.Repo
  alias AIBrain.AgentRuntime.GoalDaemon
  alias AIBrain.Data.Goal, as: Schema
  alias AIBrain.Data.{EpisodicMemories, EpisodicMemory, Goals, RunContextRefs, Runs}
  alias AIBrain.Web.Handlers.GoalsHandler
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all(EpisodicMemory)
    Repo.delete_all(Schema)
    :ok
  end

  describe "handle_list/2" do
    test "returns empty list" do
      conn = conn(:get, "/api/v1/goals")
      conn = GoalsHandler.handle_list(conn, %{})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["goals"] == []
    end

    test "returns all goals" do
      {:ok, _g1} = Goals.create(%{title: "Goal 1", status: "active"})
      {:ok, _g2} = Goals.create(%{title: "Goal 2", status: "active"})

      conn = conn(:get, "/api/v1/goals")
      conn = GoalsHandler.handle_list(conn, %{})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["goals"]) == 2
    end

    test "filters by status" do
      {:ok, _g1} = Goals.create(%{title: "Active", status: "active"})
      {:ok, _g2} = Goals.create(%{title: "Completed", status: "completed"})

      conn = conn(:get, "/api/v1/goals")
      conn = GoalsHandler.handle_list(conn, %{"status" => "active"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["goals"]) == 1
      assert hd(body["goals"])["status"] == "active"
    end
  end

  describe "handle_get/2" do
    test "returns a single goal" do
      {:ok, goal} = Goals.create(%{title: "Test Goal"})

      conn = conn(:get, "/api/v1/goals/#{goal.id}")
      conn = GoalsHandler.handle_get(conn, goal.id)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Test Goal"
      assert body["id"] == goal.id
    end

    test "returns autonomous goal runtime status" do
      {:ok, goal} =
        Goals.create(%{
          title: "Autonomous Goal",
          metadata: %{
            "autonomous" => true,
            "autonomy_level" => 2,
            "last_goal_daemon_run_id" => "run-1",
            "last_review_started_at" => "2026-05-19T13:00:00Z",
            "next_review_after" => "2026-05-19T14:00:00Z",
            "last_strategy_run_id" => "run-strategy-1",
            "last_report_artifact_id" => "artifact-1",
            "last_owner_interaction_id" => "interaction-1",
            "strategy" => %{
              "current_assessment" => "Needs sharper experiments",
              "next_actions" => ["Review metrics"]
            }
          }
        })

      conn = conn(:get, "/api/v1/goals/#{goal.id}")
      conn = GoalsHandler.handle_get(conn, goal.id)
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)

      assert body["automation"]["autonomous"] == true
      assert body["automation"]["autonomy_level"] == 2
      assert body["automation"]["last_goal_daemon_run_id"] == "run-1"
      assert body["automation"]["next_review_after"] == "2026-05-19T14:00:00Z"
      assert body["automation"]["last_strategy_run_id"] == "run-strategy-1"
      assert body["automation"]["last_report_artifact_id"] == "artifact-1"
      assert body["automation"]["last_owner_interaction_id"] == "interaction-1"
      assert body["strategy"]["current_assessment"] == "Needs sharper experiments"
    end

    test "returns 404 for missing goal" do
      conn = conn(:get, "/api/v1/goals/nonexistent")
      conn = GoalsHandler.handle_get(conn, "nonexistent")
      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Goal not found"
    end
  end

  describe "automation runtime" do
    test "scan starts due autonomous goal reviews" do
      parent = self()

      runner = fn attrs, _opts ->
        send(parent, {:goal_review, attrs.goal_id})
        {:ok, "goal-run-from-handler"}
      end

      server =
        start_supervised!(
          {GoalDaemon,
           name: :"goal_daemon_#{System.unique_integer([:positive])}",
           scan_interval: 3600,
           runner: runner}
        )

      {:ok, goal} =
        Goals.create(%{
          title: "Autonomous",
          status: "active",
          metadata: %{"autonomous" => true, "goal_daemon_cooldown_seconds" => 60}
        })

      conn = GoalsHandler.handle_scan(conn(:post, "/api/v1/goals/scan"), server)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["started_run_ids"] == ["goal-run-from-handler"]
      goal_id = goal.id
      assert_receive {:goal_review, ^goal_id}
    end

    test "run history returns runs linked by goal ref" do
      {:ok, goal} = Goals.create(%{title: "Goal with history"})

      {:ok, run} =
        Runs.create_run(%{
          source_type: "goal",
          source_id: goal.id,
          status: "completed",
          phase: "completed",
          mode: "goal_tick",
          title: "Goal review"
        })

      :ok =
        RunContextRefs.create_many(run.id, [
          %{ref_type: "goal", ref_id: goal.id, role: "parent"}
        ])

      conn = GoalsHandler.handle_runs(conn(:get, "/api/v1/goals/#{goal.id}/runs"), goal.id, %{})

      assert conn.status == 200
      assert [%{"id" => run_id, "mode" => "goal_tick"}] = Jason.decode!(conn.resp_body)["runs"]
      assert run_id == run.id
    end

    test "memory history returns goal scoped episodic memories" do
      {:ok, goal} = Goals.create(%{title: "Goal with memory"})
      {:ok, other_goal} = Goals.create(%{title: "Other goal"})

      {:ok, memory} =
        EpisodicMemories.create(%{
          goal_id: goal.id,
          run_id: "run-memory-1",
          narrative: "Weekly posting cadence increased completion quality.",
          objective: "Review self media strategy",
          approach: "run_report",
          lessons: ["Keep a fixed publishing cadence"],
          tags: ["run_report"],
          importance_score: 0.8,
          success_score: 1.0
        })

      {:ok, _other} =
        EpisodicMemories.create(%{
          goal_id: other_goal.id,
          narrative: "Unrelated goal memory"
        })

      conn =
        GoalsHandler.handle_memories(
          conn(:get, "/api/v1/goals/#{goal.id}/memories"),
          goal.id,
          %{"limit" => "10"}
        )

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["goal_id"] == goal.id
      assert [%{"id" => memory_id, "run_id" => "run-memory-1"} = item] = body["memories"]
      assert memory_id == memory.id
      assert item["narrative"] == "Weekly posting cadence increased completion quality."
      assert item["lessons"] == ["Keep a fixed publishing cadence"]
      assert item["importance_score"] == 0.8
    end

    test "memory history returns 404 for missing goal" do
      conn =
        GoalsHandler.handle_memories(
          conn(:get, "/api/v1/goals/missing/memories"),
          "missing",
          %{}
        )

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "Goal not found"
    end
  end

  describe "handle_create/2" do
    test "creates a goal with valid attrs" do
      conn = conn(:post, "/api/v1/goals")
      conn = GoalsHandler.handle_create(conn, %{"title" => "New Goal"})
      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "New Goal"
      assert body["status"] == "active"
    end

    test "returns 422 for invalid attrs" do
      conn = conn(:post, "/api/v1/goals")
      conn = GoalsHandler.handle_create(conn, %{})
      assert conn.status == 422
    end
  end

  describe "handle_update/3" do
    test "updates a goal" do
      {:ok, goal} = Goals.create(%{title: "Original"})

      conn = conn(:put, "/api/v1/goals/#{goal.id}")
      conn = GoalsHandler.handle_update(conn, goal.id, %{"title" => "Updated"})
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["title"] == "Updated"
    end

    test "returns 404 for missing goal" do
      conn = conn(:put, "/api/v1/goals/nonexistent")
      conn = GoalsHandler.handle_update(conn, "nonexistent", %{"title" => "Updated"})
      assert conn.status == 404
    end
  end

  describe "handle_delete/2" do
    test "deletes a goal" do
      {:ok, goal} = Goals.create(%{title: "To Delete"})

      conn = conn(:delete, "/api/v1/goals/#{goal.id}")
      conn = GoalsHandler.handle_delete(conn, goal.id)
      assert conn.status == 200

      assert {:error, :not_found} = Goals.get(goal.id)
    end

    test "returns 404 for missing goal" do
      conn = conn(:delete, "/api/v1/goals/nonexistent")
      conn = GoalsHandler.handle_delete(conn, "nonexistent")
      assert conn.status == 404
    end
  end
end
