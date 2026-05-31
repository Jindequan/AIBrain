defmodule AIBrain.Tool.Builtin.NotifyTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Notify

  describe "input_schema/0" do
    test "requires title and message" do
      schema = Notify.input_schema()
      assert schema["required"] == ["title", "message"]
      assert schema["type"] == "object"
    end
  end

  describe "read_only?/0" do
    test "is false (has side effects)" do
      refute Notify.read_only?()
    end
  end

  describe "risk_category/0" do
    test "is workspace_write" do
      assert Notify.risk_category() == :workspace_write
    end
  end

  describe "execute/2" do
    test "returns error for missing params" do
      assert {:error, msg} = Notify.execute(%{}, %{})
      assert String.contains?(msg, "Missing")
    end

    test "returns error when title is missing message" do
      assert {:error, msg} = Notify.execute(%{"title" => "Hello"}, %{})
      assert String.contains?(msg, "Missing")
    end
  end
end
