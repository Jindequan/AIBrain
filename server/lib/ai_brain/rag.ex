defmodule AIBrain.RAG do
  require Logger

  @moduledoc """
  Retrieval-Augmented Generation for AIBrain.

  Ingests documents from configured directories, chunks and embeds them,
  and retrieves relevant chunks for context injection.

  ## Config

      config :ai_brain, :rag_dirs, ["/path/to/docs", "/path/to/project"]
      config :ai_brain, :rag_chunk_size, 1000
      config :ai_brain, :rag_chunk_overlap, 200

  ## Integration

  Called automatically by `Context.Prepared` to inject relevant context
  into the system prompt.
  """

  @doc "Retrieve relevant context chunks for a query."
  def retrieve(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    AIBrain.RAG.Retriever.retrieve(query, limit: limit)
  end

  @doc "Format RAG results for prompt injection."
  def format_for_prompt(chunks) do
    if chunks == [] do
      ""
    else
      lines =
        Enum.map(chunks, fn chunk ->
          source = chunk.source
          content = chunk.content
          "> #{source}:\n#{String.trim(content)}"
        end)

      (["## Relevant documents", ""] ++ lines)
      |> Enum.join("\n\n")
    end
  end

  @doc "Ingest a file or directory into RAG chunks."
  def ingest(path) do
    cond do
      File.dir?(path) -> AIBrain.RAG.Ingester.ingest_directory(path)
      File.regular?(path) -> AIBrain.RAG.Ingester.ingest_file(path)
      true -> {:error, "Path not found: #{path}"}
    end
  end

  @doc "Get chunk count."
  def chunk_count do
    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, "SELECT COUNT(*) FROM rag_chunks", [])
    [[count]] = result.rows
    count
  rescue
    e ->
      Logger.error("AIBrain.RAG.chunk_count failed: #{Exception.message(e)}")
      0
  end

  @doc "Clear all RAG chunks."
  def clear do
    Ecto.Adapters.SQL.query!(AIBrain.Repo, "DELETE FROM rag_chunks", [])
    :ok
  rescue
    e ->
      Logger.error("AIBrain.RAG.clear failed: #{Exception.message(e)}")
      {:error, :clear_failed}
  end
end
