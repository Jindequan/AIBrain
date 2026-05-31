defmodule AIBrain.Tool.Builtin.WebSearch do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Web search tool — thin adapter that delegates to Business.WebSearch.
  """

  def name, do: "web_search"

  def description do
    "Search the web for current information. Returns results with titles, snippets, and URLs. " <>
      "Configure SEARXNG_URL (self-hosted, recommended) or BRAVE_API_KEY for reliable results."
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Search query"},
        "num_results" => %{
          "type" => "integer",
          "description" => "Number of results to return (default: 10, max: 20)"
        }
      },
      "required" => ["query"]
    }
  end

  def read_only?, do: true

  def execute(%{"query" => query} = args, _context) when is_binary(query) do
    num_results = min(args["num_results"] || 10, 20)

    case AIBrain.Business.WebSearch.search(query, num_results) do
      {:ok, results, source} ->
        {:ok,
         %{"query" => query, "results" => results, "count" => length(results), "source" => source}}

      {:error, reason} ->
        {:error, "Search failed: #{reason}"}
    end
  end

  def execute(%{} = args, _context) do
    {:error, "Missing required parameter: query. Got: #{inspect(args)}"}
  end
end
