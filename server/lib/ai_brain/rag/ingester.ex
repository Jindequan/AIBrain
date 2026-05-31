defmodule AIBrain.RAG.Ingester do
  @moduledoc """
  Ingests documents into the RAG chunk table.

  Reads files from configured directories or specific file paths,
  splits into chunks, generates embeddings, and stores them.
  """

  require Logger
  alias AIBrain.RAG.Chunker
  alias AIBrain.Repo

  @doc "Ingest a single file into RAG chunks."
  def ingest_file(file_path, opts \\ []) do
    with {:ok, content} <- File.read(file_path) do
      source_type = infer_source_type(file_path)
      chunks = Chunker.chunk(content, opts)

      Enum.reduce(chunks, 0, fn chunk, count ->
        case store_chunk(file_path, source_type, chunk) do
          {:ok, _id} -> count + 1
          _ -> count
        end
      end)
      |> then(fn c -> {:ok, c} end)
    else
      {:error, reason} -> {:error, "Cannot read #{file_path}: #{:file.format_error(reason)}"}
    end
  end

  @doc "Ingest all supported files from a directory."
  def ingest_directory(dir_path, opts \\ []) do
    supported = [
      "*.md",
      "*.txt",
      "*.ex",
      "*.exs",
      "*.js",
      "*.jsx",
      "*.ts",
      "*.tsx",
      "*.json",
      "*.yaml",
      "*.yml",
      "*.css",
      "*.html"
    ]

    files =
      Enum.flat_map(supported, fn pattern ->
        Path.wildcard(Path.join(dir_path, "**/" <> pattern))
      end)
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()

    total =
      Enum.reduce(files, 0, fn file, acc ->
        case ingest_file(file, opts) do
          {:ok, c} -> acc + c
          _ -> acc
        end
      end)

    Logger.info(
      "RAG.Ingester: ingested #{total} chunks from #{length(files)} files in #{dir_path}"
    )

    {:ok, total}
  end

  @doc "Run on startup: ingest from configured dirs if any."
  def startup_ingest do
    dirs = configured_dirs()

    if dirs == [] do
      Logger.info("RAG.Ingester: no rag_dirs configured, skipping startup ingest")
      {:ok, 0}
    else
      Logger.info("RAG.Ingester: startup ingest from #{inspect(dirs)}")
      reingest_all()
    end
  end

  @doc "Re-ingest all previously ingested content (clear and re-insert)."
  def reingest_all(opts \\ []) do
    # Use transaction to prevent data loss if ingest fails
    Repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(AIBrain.Repo, "DELETE FROM rag_chunks", [])

      dirs = configured_dirs()

      total =
        Enum.reduce(dirs, 0, fn dir, acc ->
          case ingest_directory(dir, opts) do
            {:ok, c} -> acc + c
            _ -> acc
          end
        end)

      {:ok, total}
    end)
  end

  defp store_chunk(source, source_type, chunk) do
    id = "rag-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    metadata = Jason.encode!(chunk.metadata)

    # Try to generate embedding, continue without it if not available
    embedding_blob =
      case AIBrain.Embeddings.embed(chunk.text) do
        {:ok, vec} -> AIBrain.Embeddings.encode_blob(vec)
        _ -> nil
      end

    try do
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        """
        INSERT INTO rag_chunks (id, source, source_type, chunk_index, content, embedding, metadata, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [id, source, source_type, chunk.index, chunk.text, embedding_blob, metadata, now]
      )

      {:ok, id}
    rescue
      e ->
        Logger.error("RAG.Ingester: failed to store chunk: #{Exception.message(e)}")
        {:error, e}
    end
  end

  defp infer_source_type(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      ext in [".ex", ".exs"] -> "elixir"
      ext in [".js", ".jsx"] -> "javascript"
      ext in [".ts", ".tsx"] -> "typescript"
      ext in [".json"] -> "json"
      ext in [".yaml", ".yml"] -> "yaml"
      ext in [".md"] -> "markdown"
      ext in [".css"] -> "css"
      ext in [".html"] -> "html"
      ext in [".txt"] -> "text"
      true -> "file"
    end
  end

  defp configured_dirs do
    case Application.get_env(:ai_brain, :rag_dirs) do
      dirs when is_list(dirs) -> dirs
      _ -> []
    end
  end
end
