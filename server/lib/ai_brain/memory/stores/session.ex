defmodule AIBrain.Memory.Stores.Session do
  @moduledoc """
  Memory store adapter for session history.

  Searches recent sessions for conversations relevant to the query.
  """

  @behaviour AIBrain.Memory.Store

  alias AIBrain.Memory.Entry
  require Logger

  @impl true
  def source, do: :session

  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    # Search session notes (summaries written by KnowledgeWiki)
    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "SELECT id, notes, inserted_at FROM sessions WHERE notes IS NOT NULL AND notes != '' ORDER BY inserted_at DESC LIMIT ?",
      [limit * 2]
    )
    |> case do
      %{rows: rows} when rows != [] ->
        rows
        |> Enum.filter(fn [_, notes, _] -> keyword_match?(notes, query) end)
        |> Enum.take(limit)
        |> Enum.map(&to_entry/1)

      _ ->
        []
    end
  rescue
    e ->
      Logger.warning("Memory.Stores.Session.search failed: #{Exception.message(e)}")
      []
  end

  @impl true
  def count do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT COUNT(*) FROM sessions WHERE notes IS NOT NULL AND notes != ''",
        []
      )

    [[count]] = result.rows
    count
  rescue
    e ->
      Logger.warning("Memory.Stores.Session.count failed: #{Exception.message(e)}")
      0
  end

  defp to_entry([id, notes, inserted_at]) do
    Entry.new(%{
      id: id,
      source: :session,
      type: :conversation,
      content: notes,
      content_hash: nil,
      confidence: 0.2,
      decay_score: 0.7,
      created_at: inserted_at,
      tags: [],
      metadata: %{session_id: id}
    })
  end

  defp keyword_match?(notes, query) when is_binary(notes) and is_binary(query) do
    query_lower = String.downcase(query)
    notes_lower = String.downcase(notes)
    words = String.split(query_lower) |> Enum.reject(&(String.length(&1) < 3))
    Enum.any?(words, &String.contains?(notes_lower, &1))
  end

  defp keyword_match?(_, _), do: false
end
