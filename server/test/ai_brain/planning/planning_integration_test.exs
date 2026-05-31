defmodule AIBrain.Planning.IntegrationTest do
  use AIBrain.DataCase

  alias AIBrain.Planning.{Agent, Executor, Collector}
  alias AIBrain.Data.{Goals, Tasks}

  describe "Agent tool handling end-to-end" do
    test "creates goal, adds tasks with depends_on, completes plan" do
      # Simulate what the planning agent would do via tool calls
      {:ok, goal} =
        Agent.handle_tool_call(
          %{
            "name" => "create_goal",
            "input" => %{
              "title" => "Integration Goal",
              "description" => "End to end integration test"
            }
          },
          %{}
        )

      assert goal.title == "Integration Goal"

      {:ok, task1} =
        Agent.handle_tool_call(
          %{
            "name" => "add_task",
            "input" => %{"goal_id" => goal.id, "title" => "Task 1", "description" => "First task"}
          },
          %{}
        )

      assert task1.title == "Task 1"
      assert task1.depends_on == []

      {:ok, task2} =
        Agent.handle_tool_call(
          %{
            "name" => "add_task",
            "input" => %{
              "goal_id" => goal.id,
              "title" => "Task 2",
              "description" => "Depends on Task 1",
              "depends_on" => [task1.id]
            }
          },
          %{}
        )

      assert task2.title == "Task 2"
      assert task2.depends_on == [task1.id]

      {:ok, result} =
        Agent.handle_tool_call(
          %{
            "name" => "complete_plan",
            "input" => %{"summary" => "Plan complete: 2 tasks"}
          },
          %{}
        )

      assert result.summary == "Plan complete: 2 tasks"

      # Verify database state
      {:ok, stored_goal} = Goals.get(goal.id)
      assert stored_goal.status == "active"

      tasks = Tasks.list_tasks(goal.id)
      assert length(tasks) == 2

      task_ids = Enum.map(tasks, & &1.id)
      assert task1.id in task_ids
      assert task2.id in task_ids
    end
  end

  describe "Executor and Collector integration" do
    test "executes completed tasks and collects results" do
      {:ok, goal} = Goals.create(%{title: "Exec Goal", description: "For execution testing"})

      {:ok, t1} =
        Tasks.create_task(%{
          goal_id: goal.id,
          title: "Task A",
          status: "completed",
          output: "done"
        })

      {:ok, _t2} =
        Tasks.create_task(%{
          goal_id: goal.id,
          title: "Task B",
          status: "pending",
          depends_on: [t1.id]
        })

      # Execute — will process the dependency graph
      {:ok, exec_result} = Executor.execute(goal.id)
      assert exec_result.goal.title == "Exec Goal"
      assert is_list(exec_result.tasks)

      # Collect
      {:ok, report} = Collector.collect(goal.id)
      assert report.stats.total == 2
      assert report.goal.title == "Exec Goal"
      assert is_binary(report.summary)
    end

    test "collector handles complex statuses" do
      {:ok, goal} = Goals.create(%{title: "Mixed Status", description: "test"})
      Tasks.create_task(%{goal_id: goal.id, title: "A", status: "completed", output: "result a"})
      Tasks.create_task(%{goal_id: goal.id, title: "B", status: "failed"})
      Tasks.create_task(%{goal_id: goal.id, title: "C", status: "cancelled"})

      {:ok, report} = Collector.collect(goal.id)
      assert report.stats.completed == 1
      assert report.stats.failed == 1
      assert report.stats.cancelled == 1
      assert report.stats.total == 3
    end
  end

  describe "Executor wave computation with real task data" do
    test "computes correct waves from persisted tasks" do
      {:ok, goal} = Goals.create(%{title: "Wave Test", description: "test"})

      {:ok, t1} = Tasks.create_task(%{goal_id: goal.id, title: "Root", depends_on: []})
      {:ok, t2} = Tasks.create_task(%{goal_id: goal.id, title: "Mid", depends_on: [t1.id]})
      {:ok, t3} = Tasks.create_task(%{goal_id: goal.id, title: "Leaf", depends_on: [t2.id]})

      tasks = Tasks.list_tasks(goal.id)
      waves = Executor.compute_waves(tasks)
      assert length(waves) == 3
      assert Enum.map(hd(waves), & &1.id) == [t1.id]
      assert Enum.map(Enum.at(waves, 1), & &1.id) == [t2.id]
      assert Enum.map(List.last(waves), & &1.id) == [t3.id]
    end
  end
end
