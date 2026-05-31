defmodule AIBrain.PromptsTest do
  use ExUnit.Case

  test "identity/0 returns a non-empty string" do
    assert is_binary(AIBrain.Prompts.identity())
    assert String.length(AIBrain.Prompts.identity()) > 100
  end

  test "personality/0 returns a style guide" do
    guide = AIBrain.Prompts.personality()
    assert is_binary(guide)
    assert String.length(guide) > 20
  end

  test "planning_agent_system/0 returns a non-empty string" do
    assert is_binary(AIBrain.Prompts.planning_agent_system())
    assert String.length(AIBrain.Prompts.planning_agent_system()) > 50
  end

  test "planning_agent_tools/0 returns 4 tool definitions" do
    tools = AIBrain.Prompts.planning_agent_tools()
    assert length(tools) == 4

    names = Enum.map(tools, & &1["name"]) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new(["create_goal", "add_task", "complete_plan", "ask_question"]),
             names
           )
  end

  test "each planning tool has name, description, and input_schema" do
    Enum.each(AIBrain.Prompts.planning_agent_tools(), fn tool ->
      assert is_binary(tool["name"])
      assert is_binary(tool["description"])
      assert is_map(tool["input_schema"])
    end)
  end

  test "proxy_identity/0 returns a non-empty string" do
    assert is_binary(AIBrain.Prompts.proxy_identity())
    assert String.length(AIBrain.Prompts.proxy_identity()) > 100
  end

  test "proxy_decision_framework/0 returns a non-empty string" do
    assert is_binary(AIBrain.Prompts.proxy_decision_framework())
    assert String.length(AIBrain.Prompts.proxy_decision_framework()) > 100
  end
end
