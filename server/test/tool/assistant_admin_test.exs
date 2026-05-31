defmodule AIBrain.Tool.Builtin.AssistantAdminTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.AssistantAdmin

  test "name and description exist" do
    assert is_binary(AssistantAdmin.name())
    assert is_binary(AssistantAdmin.description())
  end

  test "input_schema has required operation field" do
    schema = AssistantAdmin.input_schema()
    assert get_in(schema, ["required"]) == ["operation"]
  end

  test "execute returns error without operation" do
    assert {:error, _} = AssistantAdmin.execute(%{}, %{})
  end

  test "execute returns error for unknown operation" do
    assert {:error, _} = AssistantAdmin.execute(%{"operation" => "unknown"}, %{})
  end

  test "list_skills returns JSON array" do
    assert {:ok, json} = AssistantAdmin.execute(%{"operation" => "list_skills"}, %{})
    assert {:ok, _} = Jason.decode(json)
  end

  test "get_skill returns metadata for a known skill" do
    assert {:ok, json} = AssistantAdmin.execute(%{"operation" => "get_skill", "name" => "coding"}, %{})
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["name"] == "coding"
    assert is_binary(decoded["description"])
  end

  test "load_skill returns full body for a known skill" do
    assert {:ok, json} = AssistantAdmin.execute(%{"operation" => "load_skill", "name" => "coding"}, %{})
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["name"] == "coding"
    assert is_binary(decoded["body"])
    assert String.length(decoded["body"]) > 100
  end

  test "load_skill returns error for unknown skill" do
    assert {:error, msg} = AssistantAdmin.execute(%{"operation" => "load_skill", "name" => "nonexistent"}, %{})
    assert is_binary(msg)
  end
end
