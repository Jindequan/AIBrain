defmodule AIBrain.Tool.Builtin.DocRead do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Document reader tool — thin adapter that delegates to Business.Document.
  """

  alias AIBrain.Business.Document

  def name, do: "doc_read"

  def description do
    "Read document files (PDF, Word, Excel, RTF, HTML, CSV, Markdown, etc.) and return their text content. " <>
      "Supports: #{Enum.join(Document.supported_exts(), ", ")}"
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "Path to the document file"},
        "max_chars" => %{
          "type" => "integer",
          "description" => "Maximum characters to return (default: 20000)"
        }
      },
      "required" => ["path"]
    }
  end

  def read_only?, do: true

  def execute(%{"path" => path} = args, context) do
    resolved = Document.resolve_path(path, context)
    Document.extract_text(resolved, max_chars: args["max_chars"])
  end
end
