defmodule AIBrain.Memory.Stores.KnowledgeWiki do
  @moduledoc """
  Memory store adapter for KnowledgeWiki entries.

  Wraps AIBrain.KnowledgeWiki to produce unified Memory.Entry structs.
  """

  @behaviour AIBrain.Memory.Store

  alias AIBrain.Memory.Entry
  require Logger

  @impl true
  def source, do: :knowledge_wiki

  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    AIBrain.KnowledgeWiki.query_by_relevance(query, limit: limit)
    |> Enum.map(&to_entry/1)
  end

  @impl true
  def count do
    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, "SELECT COUNT(*) FROM knowledge_entries", [])
    [[count]] = result.rows
    count
  rescue
    e ->
      Logger.warning("Memory.Stores.KnowledgeWiki.count failed: #{Exception.message(e)}")
      0
  end

  defp to_entry(row) when is_map(row) do
    Entry.new(%{
      id: Map.get(row, :id),
      source: :knowledge_wiki,
      type: safe_type_atom(Map.get(row, :type, "fact")),
      content: Map.get(row, :content, ""),
      content_hash: nil,
      embedding: Map.get(row, :embedding),
      confidence: Map.get(row, :confidence, 0.5),
      decay_score: Map.get(row, :decay_score, 1.0),
      created_at: Map.get(row, :created_at),
      tags: Map.get(row, :tags, []),
      metadata: %{
        source_session_id: Map.get(row, :source_session_id)
      }
    })
  end

  @known_types ~w(fact preference learning rule template note)
  defp safe_type_atom(s) when is_binary(s) and s in @known_types, do: String.to_atom(s)
  defp safe_type_atom(_), do: :fact
end
