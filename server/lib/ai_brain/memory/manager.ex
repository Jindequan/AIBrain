defmodule AIBrain.Memory.Manager do
  @moduledoc """
  Unified Memory Manager — single entry point for searching all memory stores.

  Parallel queries across KnowledgeWiki, RAG, Session, and Workspace,
  then deduplicates and fuses scores into a single ranked result list.

  Source weight allocation:
    - knowledge_wiki: 0.40  (most reliable — distilled from past conversations)
    - rag:             0.30  (document chunks with semantic search)
    - session:         0.20  (recent conversation notes, lower confidence)
    - workspace:       0.10  (raw file content, least structured)
  """

  require Logger

  @stores [
    AIBrain.Memory.Stores.KnowledgeWiki,
    AIBrain.Memory.Stores.RAG,
    AIBrain.Memory.Stores.Session,
    AIBrain.Memory.Stores.Workspace
  ]

  @source_weights %{
    knowledge_wiki: 0.40,
    rag: 0.30,
    session: 0.20,
    workspace: 0.10
  }

  @doc """
  Search all memory stores for entries relevant to the query.

  Options:
    - :limit — max results (default 10)
    - :sources — restrict to specific sources (default: all)
    - :deduplicate — whether to deduplicate (default: true)

  Returns ranked list of Entry structs.
  """
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) and query != "", do: do_search(query, opts)
  def search(_query, _opts), do: []

  defp do_search(query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    sources = Keyword.get(opts, :sources, @stores)
    dedup? = Keyword.get(opts, :deduplicate, true)

    results =
      sources
      |> search_stores(query, limit)
      |> fuse_scores()
      |> maybe_deduplicate(dedup?)
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(limit)

    results
  rescue
    e ->
      Logger.error("Memory.Manager.search failed: #{Exception.message(e)}")
      []
  end

  @doc """
  Count total entries across all stores.
  """
  def total_entries do
    if parallel_enabled?() do
      @stores
      |> Task.async_stream(& &1.count(), timeout: 3_000, on_timeout: :kill_task)
      |> Enum.reduce(0, fn
        {:ok, count}, acc -> acc + count
        _, acc -> acc
      end)
    else
      Enum.reduce(@stores, 0, fn store, acc -> acc + safe_count(store) end)
    end
  end

  @doc """
  Format search results for LLM prompt injection.
  """
  def format_for_prompt(entries) do
    if entries == [] do
      ""
    else
      lines =
        Enum.map(entries, fn entry ->
          source_label = source_label(entry.source)
          "- [#{entry.type}] [#{source_label}] #{entry.content}"
        end)

      (["## Memory (from all sources)", ""] ++ lines)
      |> Enum.join("\n")
    end
  end

  # ── Score Fusion ────────────────────────────────────────────────

  defp fuse_scores(entries) do
    Enum.map(entries, fn entry ->
      weight = Map.get(@source_weights, entry.source, 0.1)
      decay = entry.decay_score || 1.0
      %{entry | confidence: entry.confidence * weight * decay}
    end)
  end

  defp search_stores(sources, query, limit) do
    if parallel_enabled?() do
      sources
      |> Task.async_stream(
        fn store ->
          store.search(query, limit: limit)
        end,
        timeout: 5_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, entries} -> entries
        {:exit, _reason} -> []
      end)
    else
      Enum.flat_map(sources, &safe_search(&1, query, limit))
    end
  end

  defp safe_search(store, query, limit) do
    store.search(query, limit: limit)
  rescue
    e ->
      Logger.warning("Memory.Manager: #{inspect(store)} search failed: #{Exception.message(e)}")
      []
  end

  defp safe_count(store) do
    store.count()
  rescue
    e ->
      Logger.warning("Memory.Manager: #{inspect(store)} count failed: #{Exception.message(e)}")
      0
  end

  defp parallel_enabled? do
    Application.get_env(:ai_brain, :memory_parallelism, true)
  end

  # ── Deduplication ───────────────────────────────────────────────

  defp maybe_deduplicate(entries, false), do: entries

  defp maybe_deduplicate(entries, true) do
    entries
    |> Enum.group_by(&content_key/1)
    |> Enum.flat_map(fn {_, group} ->
      case group do
        [single] -> [single]
        multiple -> [Enum.max_by(multiple, & &1.confidence)]
      end
    end)
  end

  # Generates a dedup key: normalize content → first ~100 chars as fingerprint
  defp content_key(entry) do
    content = String.downcase(String.trim(entry.content))
    String.slice(content, 0..min(String.length(content), 100))
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp source_label(:knowledge_wiki), do: "memory"
  defp source_label(:rag), do: "docs"
  defp source_label(:session), do: "history"
  defp source_label(:workspace), do: "workspace"
end
