defmodule AIBrain.Business.Document.Extractor do
  @moduledoc """
  Format-specific document text extractors.

  Each function handles one file format using the appropriate
  external tool or native parser.
  """

  # -- PDF --

  def extract(path, ".pdf") do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, "pdftotext not found. Install poppler-utils: brew install poppler"}

      exe ->
        case System.cmd(exe, ["-layout", path, "-"], stderr_to_stdout: false) do
          {text, 0} -> {:ok, text}
          {err, _} -> {:error, "pdftotext failed: #{String.slice(err, 0, 200)}"}
        end
    end
  end

  # -- Word / RTF / ODT (macOS textutil) --

  def extract(path, ext) when ext in [".docx", ".doc", ".rtf", ".odt"] do
    case System.find_executable("textutil") do
      nil ->
        {:error, "textutil not available (macOS only)"}

      exe ->
        case System.cmd(exe, ["-convert", "txt", "-stdout", path], stderr_to_stdout: false) do
          {text, 0} -> {:ok, text}
          {err, _} -> {:error, "textutil failed: #{String.slice(err, 0, 200)}"}
        end
    end
  end

  # -- Excel (via Python openpyxl) --

  def extract(path, ext) when ext in [".xlsx", ".xls"] do
    python = System.find_executable("python3") || System.find_executable("python")

    if python do
      script = """
      import sys
      try:
          import openpyxl
          wb = openpyxl.load_workbook(sys.argv[1], read_only=True, data_only=True)
          for sheet in wb.sheetnames:
              ws = wb[sheet]
              print(f"=== Sheet: {sheet} ===")
              for row in ws.iter_rows(values_only=True):
                  print("\\t".join(str(c) if c is not None else "" for c in row))
      except ImportError:
          print("openpyxl not installed, run: pip install openpyxl")
          sys.exit(1)
      """

      case System.cmd(python, ["-c", script, path], stderr_to_stdout: false) do
        {text, 0} -> {:ok, text}
        {err, _} -> {:error, "Excel reading failed: #{String.slice(err, 0, 200)}"}
      end
    else
      {:error, "Python not available for Excel reading. Install python3 or convert to CSV first."}
    end
  end

  # -- CSV --

  def extract(path, ".csv") do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Cannot read CSV: #{:file.format_error(reason)}"}
    end
  end

  # -- HTML --

  def extract(path, ext) when ext in [".html", ".htm"] do
    case File.read(path) do
      {:ok, html} ->
        text =
          html
          |> String.replace(~r/<script[^>]*>.*?<\/script>/si, " ")
          |> String.replace(~r/<style[^>]*>.*?<\/style>/si, " ")
          |> String.replace(~r/<br\s*\/?>/i, "\n")
          |> String.replace(~r/<\/?(p|div|h[1-6]|li|tr|td|th)[^>]*>/i, "\n")
          |> String.replace(~r/<[^>]+>/, "")
          |> HtmlEntities.decode()
          |> String.replace(~r/\n{3,}/, "\n\n")

        {:ok, text}

      {:error, reason} ->
        {:error, "Cannot read HTML: #{:file.format_error(reason)}"}
    end
  end

  # -- Plain text formats --

  def extract(path, ext) when ext in [".md", ".txt", ".json", ".yaml", ".yml", ".xml"] do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Cannot read file: #{:file.format_error(reason)}"}
    end
  end
end
