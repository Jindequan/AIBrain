defmodule AIBrain.Memory.Stores.RAG do
  @moduledoc """
  Memory store adapter for RAG chunks.

  Wraps AIBrain.RAG to produce unified Memory.Entry structs.
  """

  @behaviour AIBrain.Memory.Store

  alias AIBrain.Memory.Entry
  require Logger

  @impl true
  def source, do: :rag

  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    AIBrain.RAG.retrieve(query, limit: limit)
    |> Enum.map(&to_entry/1)
  end

  @impl true
  def count do
    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, "SELECT COUNT(*) FROM rag_chunks", [])
    [[count]] = result.rows
    count
  rescue
    e ->
      Logger.warning("Memory.Stores.RAG.count failed: #{Exception.message(e)}")
      0
  end

  defp to_entry(chunk) when is_map(chunk) do
    Entry.new(%{
      id: Map.get(chunk, :id, "rag-#{System.unique_integer([:positive])}"),
      source: :rag,
      type: :document,
      content: Map.get(chunk, :content, ""),
      content_hash: nil,
      embedding: Map.get(chunk, :embedding),
      confidence: Map.get(chunk, :score, 0.3) / 1.0,
      decay_score: 1.0,
      created_at: nil,
      tags: [],
      metadata: %{
        source_file: Map.get(chunk, :source)
      }
    })
  end
end
