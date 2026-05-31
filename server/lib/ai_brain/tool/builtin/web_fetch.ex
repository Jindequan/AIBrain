defmodule AIBrain.Tool.Builtin.WebFetch do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Web fetch tool — thin adapter that delegates to Business.WebContent.
  """

  def name, do: "web_fetch"

  def description do
    "Fetch and extract content from a web page. Returns the main text content, title, and metadata."
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{"type" => "string", "description" => "URL to fetch"},
        "extract_format" => %{
          "type" => "string",
          "enum" => ["text", "markdown", "html"],
          "description" => "Output format (default: text)"
        }
      },
      "required" => ["url"]
    }
  end

  def read_only?, do: true

  def execute(%{"url" => url} = args, _context) when is_binary(url) do
    format = args["extract_format"] || "text"
    AIBrain.Business.WebContent.fetch_and_extract(url, format)
  end

  def execute(%{} = args, _context) do
    {:error, "Missing required parameter: url. Got: #{inspect(args)}"}
  end
end
