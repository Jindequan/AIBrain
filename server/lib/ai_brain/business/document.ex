defmodule AIBrain.Business.Document do
  @moduledoc """
  Document text extraction business layer.

  Reads various document formats and returns plain text content.
  Supports PDF, Word, Excel, RTF, HTML, CSV, Markdown, JSON, YAML, XML.

  The Tool layer should call `extract_text/1` — never call format-specific
  extractors directly.
  """

  alias AIBrain.Business.Document.Extractor

  @supported_exts ~w(.pdf .docx .doc .rtf .odt .xlsx .xls .csv .md .txt .json .yaml .yml .html .htm .xml)

  def supported_exts, do: @supported_exts

  @doc """
  Extract text from a document file.

  Returns `{:ok, %{"path", "text", "char_count", "truncated"}}` or `{:error, reason}`.
  """
  def extract_text(path, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, 20_000)
    ext = path |> Path.extname() |> String.downcase()

    cond do
      not File.exists?(path) ->
        {:error, "File not found: #{path}"}

      ext not in @supported_exts ->
        {:error, "Unsupported file type: #{ext}. Supported: #{Enum.join(@supported_exts, ", ")}"}

      true ->
        case Extractor.extract(path, ext) do
          {:ok, text} ->
            text = String.trim(text)
            truncated = String.length(text) > max_chars
            output = String.slice(text, 0, max_chars)

            {:ok,
             %{
               "path" => path,
               "text" => output,
               "char_count" => String.length(output),
               "truncated" => truncated
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Resolve a relative path against a working directory.
  """
  def resolve_path(path, context) do
    cwd = context[:cwd]

    if cwd && Path.type(path) not in [:absolute, :vms] do
      Path.expand(path, cwd)
    else
      path
    end
  end
end
