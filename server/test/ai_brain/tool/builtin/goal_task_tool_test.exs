defmodule AIBrain.Tool.Builtin.GoalTaskToolTest do
  use AIBrain.DataCase

  alias AIBrain.Tool.Builtin.GoalTaskTool
  alias AIBrain.Data.{Interactions, Tasks}

  describe "create_goal" do
    test "creates a goal and returns its id" do
      result =
        GoalTaskTool.execute(
          %{
            "operation" => "create_goal",
            "title" => "用户权限系统设计完成",
            "description" => "设计方案通过评审，可指导实现"
          },
          %{}
        )

      assert {:ok, output} = result
      assert output =~ "goal_id"
    end
  end

  describe "create_task" do
    test "creates a task under a goal" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Test Goal"})

      result =
        GoalTaskTool.execute(
          %{
            "operation" => "create_task",
            "goal_id" => goal.id,
            "title" => "架构设计",
            "description" => "设计系统架构",
            "assigned_assistant" => "architect"
          },
          %{}
        )

      assert {:ok, output} = result
      assert output =~ "task_id"
    end

    test "uses run context when goal_id is omitted and records provenance metadata" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Autonomous Goal"})

      assert {:ok, output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "create_task",
                   "title" => "Review account metrics",
                   "description" =>
                     "Check recent performance and propose next content experiments"
                 },
                 %{
                   run_id: "run-goal-123",
                   source_type: "goal",
                   goal_id: goal.id,
                   task_id: "source-task-1",
                   schedule_id: "schedule-1",
                   workspace_path: "/tmp/goal-workspace",
                   autonomy_level: 2
                 }
               )

      %{"task_id" => task_id, "goal_id" => returned_goal_id, "created_by_run_id" => created_by} =
        Jason.decode!(output)

      assert returned_goal_id == goal.id
      assert created_by == "run-goal-123"

      {:ok, task} = AIBrain.Data.Tasks.get_task(task_id)
      assert task.goal_id == goal.id
      assert task.metadata["created_by_run_id"] == "run-goal-123"
      assert task.metadata["created_by_source_type"] == "goal"
      assert task.metadata["source_task_id"] == "source-task-1"
      assert task.metadata["schedule_id"] == "schedule-1"
      assert task.metadata["workspace_path"] == "/tmp/goal-workspace"
      assert task.metadata["autonomy_level"] == 2
    end
  end

  describe "list_goals" do
    test "returns active goals" do
      AIBrain.Data.Goals.create(%{title: "Goal A"})
      AIBrain.Data.Goals.create(%{title: "Goal B"})

      assert {:ok, output} = GoalTaskTool.execute(%{"operation" => "list_goals"}, %{})
      assert output =~ "Goal A"
    end
  end

  describe "update_task_status" do
    test "marks a task completed with output" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "G"})

      {:ok, task} =
        AIBrain.Data.Tasks.create_task(%{title: "T", goal_id: goal.id, status: "running"})

      assert {:ok, _} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "update_task_status",
                   "task_id" => task.id,
                   "status" => "completed",
                   "output" => "架构设计文档已完成"
                 },
                 %{}
               )

      {:ok, updated} = AIBrain.Data.Tasks.get_task(task.id)
      assert updated.status == "completed"
      assert updated.output == "架构设计文档已完成"
    end
  end

  describe "record_goal_strategy" do
    test "records structured long-term strategy on goal metadata" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Creator account"})

      assert {:ok, output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "record_goal_strategy",
                   "current_assessment" => "Growth is constrained by unclear content pillars.",
                   "next_actions" => ["Analyze top 10 posts", "Draft two experiments", ""],
                   "blockers" => ["Need platform analytics access"],
                   "needs_owner_input" => true,
                   "next_focus" => "Validate content pillars",
                   "review_after_seconds" => 1800
                 },
                 %{goal_id: goal.id, run_id: "run-goal-1"}
               )

      body = Jason.decode!(output)
      assert body["goal_id"] == goal.id
      assert body["strategy"]["next_actions"] == ["Analyze top 10 posts", "Draft two experiments"]
      assert body["next_review_after"]

      {:ok, updated} = AIBrain.Data.Goals.get(goal.id)
      assert updated.metadata["strategy"]["current_assessment"] =~ "Growth is constrained"
      assert updated.metadata["strategy"]["needs_owner_input"] == true
      assert updated.metadata["strategy"]["updated_by_run_id"] == "run-goal-1"
      assert updated.metadata["last_strategy_run_id"] == "run-goal-1"
      assert updated.metadata["next_review_after"]
    end

    test "creates owner interaction when strategy needs owner input" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Health management"})

      assert {:ok, output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "record_goal_strategy",
                   "current_assessment" => "Need access to health data before advice.",
                   "blockers" => ["Health data source is not connected"],
                   "next_actions" => ["Wait for data access", "Review latest metrics"],
                   "needs_owner_input" => true,
                   "next_focus" => "Data ingestion"
                 },
                 %{goal_id: goal.id, run_id: "run-health-1", source_type: "goal"}
               )

      body = Jason.decode!(output)
      interaction_id = body["owner_interaction_id"]
      assert is_binary(interaction_id)

      interaction = Interactions.get(interaction_id)
      assert interaction.type == "form"
      assert interaction.status == "pending"
      assert interaction.context["kind"] == "goal_owner_input"
      assert interaction.context["goal_id"] == goal.id
      assert interaction.context["run_id"] == "run-health-1"
      assert interaction.schema_data["prompt"] =~ "Health data source is not connected"

      {:ok, updated} = AIBrain.Data.Goals.get(goal.id)
      assert updated.metadata["last_owner_interaction_id"] == interaction_id
      assert updated.metadata["last_owner_interaction_requested_at"]
    end

    test "materializes next actions into deduplicated tasks when no owner input is needed" do
      {:ok, goal} =
        AIBrain.Data.Goals.create(%{
          title: "Creator account",
          priority: 4,
          workspace_path: "/tmp/creator-workspace",
          metadata: %{"autonomy_level" => 2}
        })

      args = %{
        "operation" => "record_goal_strategy",
        "current_assessment" => "Ready to execute content experiments.",
        "next_actions" => ["Analyze top posts", "Draft two experiments"],
        "needs_owner_input" => false,
        "next_focus" => "Execution"
      }

      assert {:ok, first_output} =
               GoalTaskTool.execute(args, %{
                 goal_id: goal.id,
                 run_id: "run-strategy-1",
                 source_type: "goal"
               })

      first_body = Jason.decode!(first_output)
      assert length(first_body["tasks"]["created"]) == 2
      assert first_body["tasks"]["existing"] == []

      tasks = Tasks.list_tasks(goal.id)

      assert Enum.sort(Enum.map(tasks, & &1.title)) == [
               "Analyze top posts",
               "Draft two experiments"
             ]

      assert Enum.all?(tasks, &(&1.metadata["origin"] == "goal_strategy"))
      assert Enum.all?(tasks, &is_binary(&1.metadata["strategy_action_key"]))
      assert Enum.all?(tasks, &(&1.metadata["created_by_run_id"] == "run-strategy-1"))
      assert Enum.all?(tasks, &(&1.metadata["workspace_path"] == "/tmp/creator-workspace"))
      assert Enum.all?(tasks, &(&1.metadata["autonomy_level"] == 2))

      assert {:ok, second_output} =
               GoalTaskTool.execute(args, %{
                 goal_id: goal.id,
                 run_id: "run-strategy-2",
                 source_type: "goal"
               })

      second_body = Jason.decode!(second_output)
      assert second_body["tasks"]["created"] == []

      assert Enum.sort(second_body["tasks"]["existing"]) ==
               Enum.sort(first_body["tasks"]["created"])

      assert length(Tasks.list_tasks(goal.id)) == 2
    end

    test "does not materialize next actions while waiting for owner input" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Health management"})

      assert {:ok, output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "record_goal_strategy",
                   "current_assessment" => "Need owner authorization.",
                   "next_actions" => ["Connect health data"],
                   "blockers" => ["Health data permission missing"],
                   "needs_owner_input" => true
                 },
                 %{goal_id: goal.id, run_id: "run-health-1"}
               )

      body = Jason.decode!(output)
      assert body["owner_interaction_id"]
      assert body["tasks"]["skipped"] == "needs_owner_input"
      assert Tasks.list_tasks(goal.id) == []
    end

    test "reuses existing pending owner interaction for the goal" do
      {:ok, goal} = AIBrain.Data.Goals.create(%{title: "Creator account"})

      assert {:ok, first_output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "record_goal_strategy",
                   "current_assessment" => "Needs account access.",
                   "blockers" => ["No analytics permission"],
                   "needs_owner_input" => true
                 },
                 %{goal_id: goal.id, run_id: "run-1"}
               )

      first_id = Jason.decode!(first_output)["owner_interaction_id"]

      assert {:ok, second_output} =
               GoalTaskTool.execute(
                 %{
                   "operation" => "record_goal_strategy",
                   "current_assessment" => "Still needs account access.",
                   "blockers" => ["No analytics permission"],
                   "needs_owner_input" => true
                 },
                 %{goal_id: goal.id, run_id: "run-2"}
               )

      assert Jason.decode!(second_output)["owner_interaction_id"] == first_id
    end
  end
end
