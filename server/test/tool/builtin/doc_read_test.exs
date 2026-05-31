defmodule AIBrain.Tool.Builtin.DocReadTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Builtin.DocRead

  describe "name/0" do
    test "returns tool name" do
      assert DocRead.name() == "doc_read"
    end
  end

  describe "description/0" do
    test "returns description with supported formats" do
      desc = DocRead.description()
      assert desc =~ "PDF"
      assert desc =~ "Word"
      assert desc =~ "Excel"
      assert desc =~ ".pdf"
    end
  end

  describe "input_schema/0" do
    test "defines required path property" do
      schema = DocRead.input_schema()
      assert schema["properties"]["path"]["type"] == "string"
      assert schema["required"] == ["path"]
    end

    test "defines optional max_chars property" do
      schema = DocRead.input_schema()
      assert schema["properties"]["max_chars"]["type"] == "integer"
      assert "max_chars" not in schema["required"]
    end
  end

  describe "read_only?/0" do
    test "is read-only" do
      assert DocRead.read_only?() == true
    end
  end
end
