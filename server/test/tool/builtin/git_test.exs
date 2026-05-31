defmodule AIBrain.Tool.Builtin.GitTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Builtin.Git

  describe "name/0" do
    test "returns tool name" do
      assert Git.name() == "git"
    end
  end

  describe "description/0" do
    test "returns Git version control description" do
      desc = Git.description()
      assert desc =~ "Git"
      assert desc =~ "version control"
      assert desc =~ "status"
      assert desc =~ "commit"
    end
  end

  describe "input_schema/0" do
    test "defines action property with enum" do
      schema = Git.input_schema()
      assert schema["properties"]["action"]["type"] == "string"
      assert is_list(schema["properties"]["action"]["enum"])
      assert "status" in schema["properties"]["action"]["enum"]
      assert "commit" in schema["properties"]["action"]["enum"]
      assert "push" in schema["properties"]["action"]["enum"]
    end

    test "defines optional message property" do
      schema = Git.input_schema()
      assert schema["properties"]["message"]["type"] == "string"
      assert "message" not in schema["required"]
    end
  end

  describe "read_only?/0" do
    test "is not read-only" do
      assert Git.read_only?() == false
    end
  end
end
