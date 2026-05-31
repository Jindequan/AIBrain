defmodule AIBrain.Memory do
  @moduledoc """
  Unified facade over all AIBrain memory stores.

  Provides a single API for remembering, recalling, and forgetting
  across episodic memories, semantic knowledge (KnowledgeWiki),
  session notes, and document chunks (RAG).

  Use this module instead of interacting with individual stores directly.
  """

  require Logger

  @doc """
  Store a memory entry.

  ## Options

    * `:type` — one of `:episodic`, `:semantic`, `:note` (default `:semantic`)
    * `:goal_id` — **(required for `:episodic`)** the goal this memory belongs to
    * `:session_id` — **(required for `:note`)** the session to attach the note to
    * `:entry_type` — for `:semantic` entries: `"fact"`, `"preference"`, `"learning"`,
      `"task_outcome"`, `"failure_pattern"` (default `"fact"`)
    * `:tags` — list of tag strings
    * `:confidence` — float 0.0–1.0 (default 0.5)
    * Type-specific options are passed through to the underlying store

  ## Examples

      AIBrain.Memory.remember("User prefers dark mode", type: :semantic)
      AIBrain.Memory.remember("Completed migration", type: :episodic, goal_id: "g-123")
      AIBrain.Memory.remember("Discussed timeline", type: :note, session_id: "s-456")
  """
  def remember(text, opts \\ []) when is_binary(text) and is_list(opts) do
    type = Keyword.get(opts, :type, :semantic)

    case type do
      :episodic -> remember_episodic(text, opts)
      :semantic -> remember_semantic(text, opts)
      :note -> remember_note(text, opts)
    end
  end

  @doc """
  Search memory across all stores or filter by type.

  Returns `{:ok, list_of_maps}` where each entry map includes `:content`,
  `:source`, `:score`, `:type`, `:id`, `:created_at`, `:lessons`,
  and `:metadata`.

  ## Options

    * `:type` — filter to one store (`:episodic`, `:semantic`, `:note`); omit for all
    * `:limit` — max results (default 10)
    * All other options are passed through to the underlying store

  ## Examples

      {:ok, results} = AIBrain.Memory.recall("user preferences")
      {:ok, episodes} = AIBrain.Memory.recall("g-123", type: :episodic, limit: 5)
  """
  def recall(query, opts \\ [])

  def recall("", _opts), do: {:ok, []}

  def recall(query, opts) when is_binary(query) do
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 10)

    entries =
      case type do
        :episodic -> search_episodic(query, limit)
        :semantic -> search_semantic(query, limit)
        :note -> search_note(query, limit)
        nil -> search_all(query, opts)
      end

    {:ok, entries}
  end

  def recall(_query, _opts), do: {:ok, []}

  @doc """
  Remove a memory entry by ID and type.

  ## Examples

      AIBrain.Memory.forget("kw-12345", :semantic)
      AIBrain.Memory.forget("uuid-abc", :episodic)
  """
  def forget(id, :semantic) do
    AIBrain.KnowledgeWiki.delete(id)
  end

  def forget(id, :episodic) do
    try do
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "DELETE FROM episodic_memories WHERE id = ?",
        [id]
      )

      :ok
    rescue
      e ->
        Logger.warning("Memory.forget(:episodic) failed: #{Exception.message(e)}")
        {:error, :not_found}
    end
  end

  def forget(id, :note) do
    try do
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "UPDATE sessions SET notes = NULL WHERE id = ?",
        [id]
      )

      :ok
    rescue
      e ->
        Logger.warning("Memory.forget(:note) failed: #{Exception.message(e)}")
        {:error, :not_found}
    end
  end

  @doc """
  Format recall results as a string for LLM prompt injection.

  Accepts either the map format returned by `recall/2` or `Entry` structs.

  ## Examples

      {:ok, entries} = AIBrain.Memory.recall("preferences")
      prompt_section = AIBrain.Memory.context_text(entries)
  """
  def context_text(entries) when is_list(entries) do
    if entries == [] do
      ""
    else
      lines =
        Enum.map(entries, fn entry ->
          src = entry_value(entry, :source)
          typ = entry_value(entry, :type)
          content = entry_value(entry, :content)
          "- [#{typ}] [#{source_label(src)}] #{content}"
        end)

      (["## Memory (from all sources)", ""] ++ lines)
      |> Enum.join("\n")
    end
  end

  @doc """
  Return entry counts per store type for diagnostics.

  ## Examples

      AIBrain.Memory.stats()
      # => %{episodic: 42, semantic: 128, note: 15, rag: 300}
  """
  def stats do
    %{
      episodic: count_table("episodic_memories"),
      semantic: count_store(AIBrain.Memory.Stores.KnowledgeWiki),
      note: count_notes(),
      rag: count_store(AIBrain.Memory.Stores.RAG)
    }
  end

  # ── Private: remember ─────────────────────────────────────────────

  defp remember_episodic(text, opts) do
    goal_id = Keyword.get(opts, :goal_id)

    unless goal_id do
      raise ArgumentError, "`:goal_id` is required for :episodic memory type"
    end

    attrs = %{
      narrative: text,
      goal_id: goal_id,
      task_id: Keyword.get(opts, :task_id),
      run_id: Keyword.get(opts, :run_id),
      objective: Keyword.get(opts, :objective),
      approach: Keyword.get(opts, :approach),
      success_score: Keyword.get(opts, :success_score, 0.0),
      importance_score: Keyword.get(opts, :importance_score, 0.0),
      lessons: Keyword.get(opts, :lessons, []),
      tags: Keyword.get(opts, :tags, [])
    }

    case AIBrain.Data.EpisodicMemories.create(attrs) do
      {:ok, memory} -> {:ok, memory}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp remember_semantic(text, opts) do
    type = Keyword.get(opts, :entry_type, "fact")
    tags = Keyword.get(opts, :tags, [])
    confidence = Keyword.get(opts, :confidence, 0.5)
    session_id = Keyword.get(opts, :session_id)
    content_hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    try do
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        """
        INSERT OR IGNORE INTO knowledge_entries
          (id, type, content, content_hash, tags, source_type, source_session_id,
           confidence, decay_score, created_at, updated_at, last_confirmed_at)
        VALUES (?, ?, ?, ?, ?, 'session', ?, ?, 1.0, ?, ?, ?)
        """,
        [
          "kw-#{System.unique_integer([:positive])}",
          type,
          text,
          content_hash,
          Jason.encode!(tags),
          session_id,
          confidence,
          now,
          now,
          now
        ]
      )

      {:ok, %{id: content_hash, type: type, content: text}}
    rescue
      e ->
        Logger.error("Memory.remember(:semantic) failed: #{Exception.message(e)}")
        {:error, :store_failed}
    end
  end

  defp remember_note(text, opts) do
    session_id = Keyword.get(opts, :session_id)

    unless session_id do
      raise ArgumentError, "`:session_id` is required for :note memory type"
    end

    try do
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "UPDATE sessions SET notes = ? WHERE id = ?",
        [text, session_id]
      )

      {:ok, %{session_id: session_id, note: text}}
    rescue
      e ->
        Logger.warning("Memory.remember(:note) failed: #{Exception.message(e)}")
        {:error, :store_failed}
    end
  end

  # ── Private: recall ───────────────────────────────────────────────

  defp search_episodic(goal_id, limit) do
    AIBrain.Data.EpisodicMemories.get_by_goal(goal_id, limit: limit)
    |> Enum.map(fn e ->
      %{
        content: e.narrative,
        source: :episodic,
        score: e.importance_score || 0.0,
        type: :episodic,
        id: e.id,
        created_at: e.inserted_at,
        lessons: e.lessons || [],
        metadata: %{
          goal_id: e.goal_id,
          success_score: e.success_score,
          key_decisions: e.key_decisions || %{},
          period_start: e.period_start,
          period_end: e.period_end
        }
      }
    end)
  end

  defp search_semantic(query, limit) do
    AIBrain.Memory.Stores.KnowledgeWiki.search(query, limit: limit)
    |> Enum.map(fn entry ->
      %{
        content: entry.content,
        source: :semantic,
        score: entry.confidence,
        type: entry.type,
        id: entry.id,
        created_at: entry.created_at,
        lessons: [],
        metadata: entry.metadata || %{}
      }
    end)
  end

  defp search_note(query, limit) do
    AIBrain.Memory.Stores.Session.search(query, limit: limit)
    |> Enum.map(fn entry ->
      %{
        content: entry.content,
        source: :note,
        score: entry.confidence,
        type: :conversation,
        id: entry.id,
        created_at: entry.created_at,
        lessons: [],
        metadata: entry.metadata || %{}
      }
    end)
  end

  defp search_all(query, opts) do
    AIBrain.Memory.Manager.search(query, opts)
    |> Enum.map(fn entry ->
      %{
        content: entry.content,
        source: entry.source,
        score: entry.confidence,
        type: entry.type,
        id: entry.id,
        created_at: entry.created_at,
        lessons: [],
        metadata: entry.metadata || %{}
      }
    end)
  end

  defp entry_value(entry, key) when is_map(entry) do
    Map.get(entry, key) || Map.get(entry, to_string(key))
  end

  defp entry_value(entry, key) do
    if function_exported?(entry.__struct__, :__schema__, 1) do
      Map.get(entry, key)
    else
      Map.get(Map.from_struct(entry), key)
    end
  rescue
    _ -> nil
  end

  # ── Private: stats helpers ────────────────────────────────────────

  defp count_table(table) do
    try do
      %{rows: [[count]]} =
        Ecto.Adapters.SQL.query!(AIBrain.Repo, "SELECT COUNT(*) FROM #{table}", [])

      count
    rescue
      _ -> 0
    end
  end

  defp count_notes do
    try do
      %{rows: [[count]]} =
        Ecto.Adapters.SQL.query!(
          AIBrain.Repo,
          "SELECT COUNT(*) FROM sessions WHERE notes IS NOT NULL AND notes != ''",
          []
        )

      count
    rescue
      _ -> 0
    end
  end

  defp count_store(store_module) do
    try do
      store_module.count()
    rescue
      _ -> 0
    end
  end

  # ── Private: labels ───────────────────────────────────────────────

  defp source_label(:episodic), do: "experience"
  defp source_label(:semantic), do: "memory"
  defp source_label(:note), do: "history"
  defp source_label(:knowledge_wiki), do: "memory"
  defp source_label(:rag), do: "docs"
  defp source_label(:session), do: "history"
  defp source_label(:workspace), do: "workspace"
  defp source_label(_), do: "unknown"
end
