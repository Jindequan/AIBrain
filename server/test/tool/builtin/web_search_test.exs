defmodule AIBrain.Tool.Builtin.WebSearchTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Builtin.WebSearch

  describe "name/0" do
    test "returns tool name" do
      assert WebSearch.name() == "web_search"
    end
  end

  describe "description/0" do
    test "returns tool description" do
      description = WebSearch.description()
      assert is_binary(description)
      assert String.length(description) > 0
    end
  end

  describe "input_schema/0" do
    test "returns valid schema" do
      schema = WebSearch.input_schema()
      assert schema["type"] == "object"
      assert "query" in schema["required"]
      assert schema["properties"]["query"]["type"] == "string"
    end
  end

  describe "read_only?/0" do
    test "returns true" do
      assert WebSearch.read_only?() == true
    end
  end

  describe "execute/2" do
    @tag :external
    test "searches for results" do
      # This test makes actual HTTP requests - skip in CI by default
      case System.get_env("ENABLE_EXTERNAL_TESTS") do
        "true" ->
          result = WebSearch.execute(%{"query" => "Elixir programming"}, %{})
          assert {:ok, %{"results" => results, "count" => count}} = result
          assert is_list(results)
          assert is_integer(count)
          assert count > 0

        _ ->
          :skip
      end
    end

    test "handles missing query" do
      result = WebSearch.execute(%{}, %{})
      assert {:error, message} = result
      assert String.contains?(message, "query")
    end
  end
end
