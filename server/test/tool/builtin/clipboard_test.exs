defmodule AIBrain.Tool.Builtin.ClipboardTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Clipboard

  describe "input_schema/0" do
    test "requires action" do
      schema = Clipboard.input_schema()
      assert schema["required"] == ["action"]
    end
  end

  describe "read_only?/0" do
    test "is false" do
      refute Clipboard.read_only?()
    end
  end

  describe "risk_category/0" do
    test "is workspace_write" do
      assert Clipboard.risk_category() == :workspace_write
    end
  end

  describe "execute/2" do
    test "returns error for missing action" do
      assert {:error, msg} = Clipboard.execute(%{}, %{})
      assert String.contains?(msg, "Missing")
    end

    test "returns error for unknown action" do
      assert {:error, msg} = Clipboard.execute(%{"action" => "invalid"}, %{})
      assert String.contains?(msg, "Unknown")
    end

    test "returns error for write without content" do
      assert {:error, msg} = Clipboard.execute(%{"action" => "write"}, %{})
      assert String.contains?(msg, "Missing")
    end
  end
end
