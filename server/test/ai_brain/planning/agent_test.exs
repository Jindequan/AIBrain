defmodule AIBrain.Planning.AgentTest do
  use AIBrain.DataCase

  alias AIBrain.Planning.Agent
  alias AIBrain.Data.Goals

  describe "handle_tool_call/2" do
    test "create_goal inserts and returns goal" do
      tool_call = %{
        "name" => "create_goal",
        "input" => %{"title" => "Test Goal", "description" => "A test"}
      }

      assert {:ok, result} = Agent.handle_tool_call(tool_call, %{})
      assert result.title == "Test Goal"
      assert result.id != nil

      {:ok, goal} = Goals.get(result.id)
      assert goal.title == "Test Goal"
    end

    test "add_task inserts task with depends_on" do
      {:ok, goal} = Goals.create(%{title: "G", description: "desc"})

      tool_call = %{
        "name" => "add_task",
        "input" => %{
          "goal_id" => goal.id,
          "title" => "Task A",
          "description" => "desc",
          "depends_on" => ["dep-1"]
        }
      }

      assert {:ok, result} = Agent.handle_tool_call(tool_call, %{})
      assert result.title == "Task A"
      assert result.depends_on == ["dep-1"]
    end

    test "complete_plan returns summary" do
      tool_call = %{
        "name" => "complete_plan",
        "input" => %{"summary" => "All done"}
      }

      assert {:ok, result} = Agent.handle_tool_call(tool_call, %{})
      assert result.summary == "All done"
    end

    test "ask_question returns {:ask, question, context}" do
      tool_call = %{
        "name" => "ask_question",
        "input" => %{"question" => "What priority?"}
      }

      assert {:ask, "What priority?", ctx} = Agent.handle_tool_call(tool_call, %{foo: :bar})
      assert ctx == %{foo: :bar}
    end

    test "returns error for unknown tool" do
      tool_call = %{
        "name" => "nonexistent_tool",
        "input" => %{}
      }

      assert {:error, "Unknown tool: nonexistent_tool"} = Agent.handle_tool_call(tool_call, %{})
    end

    test "create_goal with priority" do
      tool_call = %{
        "name" => "create_goal",
        "input" => %{"title" => "High Priority", "description" => "Urgent", "priority" => 1}
      }

      assert {:ok, result} = Agent.handle_tool_call(tool_call, %{})
      assert result.title == "High Priority"

      {:ok, goal} = Goals.get(result.id)
      assert goal.priority == 1
    end

    test "add_task without depends_on defaults to empty list" do
      {:ok, goal} = Goals.create(%{title: "G", description: "desc"})

      tool_call = %{
        "name" => "add_task",
        "input" => %{
          "goal_id" => goal.id,
          "title" => "Simple Task",
          "description" => "no deps"
        }
      }

      assert {:ok, result} = Agent.handle_tool_call(tool_call, %{})
      assert result.depends_on == []
    end
  end
end
