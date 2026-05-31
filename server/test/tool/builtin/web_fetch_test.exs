defmodule AIBrain.Tool.Builtin.WebFetchTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Builtin.WebFetch

  describe "name/0" do
    test "returns tool name" do
      assert WebFetch.name() == "web_fetch"
    end
  end

  describe "description/0" do
    test "returns tool description" do
      description = WebFetch.description()
      assert is_binary(description)
      assert String.length(description) > 0
    end
  end

  describe "input_schema/0" do
    test "returns valid schema" do
      schema = WebFetch.input_schema()
      assert schema["type"] == "object"
      assert "url" in schema["required"]
      assert schema["properties"]["url"]["type"] == "string"
      assert schema["properties"]["extract_format"]["enum"] == ["text", "markdown", "html"]
    end
  end

  describe "read_only?/0" do
    test "returns true" do
      assert WebFetch.read_only?() == true
    end
  end

  describe "execute/2" do
    @tag :external
    test "fetches page content as text" do
      # This test makes actual HTTP requests - skip in CI by default
      case System.get_env("ENABLE_EXTERNAL_TESTS") do
        "true" ->
          result = WebFetch.execute(%{"url" => "https://example.com"}, %{})
          assert {:ok, %{"url" => url, "title" => title, "content" => content}} = result
          assert String.contains?(url, "example.com")
          assert is_binary(title)
          assert String.length(content) > 0

        _ ->
          :skip
      end
    end

    @tag :external
    test "fetches page content as markdown" do
      case System.get_env("ENABLE_EXTERNAL_TESTS") do
        "true" ->
          result =
            WebFetch.execute(
              %{"url" => "https://example.com", "extract_format" => "markdown"},
              %{}
            )

          assert {:ok, %{"format" => "markdown"}} = result

        _ ->
          :skip
      end
    end

    test "handles missing URL" do
      result = WebFetch.execute(%{}, %{})
      assert {:error, message} = result
      assert String.contains?(message, "url")
    end

    test "handles invalid URL" do
      result = WebFetch.execute(%{"url" => "not-a-valid-url"}, %{})
      assert {:error, _message} = result
    end
  end
end
