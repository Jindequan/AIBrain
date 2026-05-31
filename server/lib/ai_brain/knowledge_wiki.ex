defmodule AIBrain.KnowledgeWiki do
  @moduledoc """
  Knowledge distillation and retrieval system.

  Distills conversation turns into structured knowledge entries
  (facts, preferences, learnings, task outcomes) and makes them
  retrievable for future context injection.

  ## Knowledge entry types

    - `fact` — objective information learned about the user or project
    - `preference` — user's stated preferences or habits
    - `learning` — insights gained from problem-solving
    - `task_outcome` — results of tasks attempted

  ## Integration

  After each successful query, `ingest_conversation/1` is called
  automatically by the agent runtime. Retrieved entries are injected
  into the system prompt by `Context.Prepared`.
  """

  require Logger

  @doc """
  Ingest a completed conversation into the knowledge base.

  Loads the conversation from `ConversationLog`, extracts knowledge
  entries via LLM, and persists them to the `knowledge_entries`
  table with deduplication.
  """
  def ingest_conversation(session_id) do
    case AIBrain.ConversationLog.load_conversation(session_id) do
      {:ok, _messages, log} ->
        turns = Map.get(log, "turns", [])
        if turns == [], do: {:ok, 0}

        entries = extract_entries(turns)
        count = persist_entries(entries, session_id)
        Logger.info("KnowledgeWiki: ingested #{count} entries from session #{session_id}")

        # Update session notes with a summary
        update_session_notes(session_id, entries)

        # Update user profile from new knowledge
        if count > 0 do
          try do
            AIBrain.Memory.UserProfile.load()
            |> AIBrain.Memory.UserProfile.update_from_entries(entries)
          rescue
            e ->
              Logger.warning(
                "KnowledgeWiki: failed to update user profile from entries: #{Exception.message(e)}"
              )

              :ok
          end
        end

        {:ok, count}

      {:error, :not_found} ->
        {:ok, 0}

      {:error, _reason} ->
        {:ok, 0}
    end
  end

  @doc """
  Distill knowledge entries from conversation turns.

  Uses an LLM call to extract structured knowledge. Falls back to
  simple pattern-based extraction if no LLM provider is available.
  """
  def extract_entries(turns) when is_list(turns) do
    conversation_text = format_conversation(turns)

    case try_llm_extraction(conversation_text) do
      {:ok, entries} when is_list(entries) ->
        entries

      _ ->
        fallback_extraction(turns)
    end
  end

  def extract_entries(_), do: []

  @doc """
  Query knowledge entries relevant to the given text.

  Returns entries sorted by relevance (decay-adjusted confidence DESC), limited to `limit`.

  Options:
    - :limit — max entries (default 10)
    - :type — filter by entry type
  """
  def query_by_relevance(text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    type_filter = Keyword.get(opts, :type)

    {where_clauses, params} = build_where_clauses(type_filter)
    where_sql = if where_clauses == [], do: "1=1", else: Enum.join(where_clauses, " AND ")

    sql = """
    SELECT id, type, content, tags, confidence, source_session_id, created_at, embedding, decay_score
    FROM knowledge_entries
    WHERE (#{where_sql})
    ORDER BY (confidence * decay_score) DESC
    LIMIT ?
    """

    params = params ++ [limit]

    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)

    entries =
      Enum.map(result.rows, fn [
                                 id,
                                 type,
                                 content,
                                 tags_json,
                                 confidence,
                                 source_session_id,
                                 created_at,
                                 embedding_blob,
                                 decay_score
                               ] ->
        %{
          id: id,
          type: type,
          content: content,
          tags: decode_tags(tags_json),
          confidence: confidence,
          source_session_id: source_session_id,
          created_at: created_at,
          embedding: embedding_blob,
          decay_score: decay_score
        }
      end)

    if text && text != "" do
      rank_by_relevance(entries, text)
    else
      entries
    end
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.query_by_relevance failed: #{Exception.message(e)}")
      []
  end

  @doc "List knowledge entries, optionally filtered by type."
  def list(opts \\ []) do
    type = Keyword.get(opts, :type)

    {where, params} =
      case type do
        nil -> {"", []}
        t -> {"WHERE type = ?", [t]}
      end

    sql =
      "SELECT id, type, content, tags, confidence, source_session_id, source_detail, usable_for_auto_decision, last_confirmed_at, created_at FROM knowledge_entries #{where} ORDER BY created_at DESC"

    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)

    Enum.map(result.rows, fn [
                               id,
                               type,
                               content,
                               tags_json,
                               confidence,
                               source_session_id,
                               source_detail,
                               usable_for_auto_decision,
                               last_confirmed_at,
                               created_at
                             ] ->
      %{
        id: id,
        type: type,
        content: content,
        tags: decode_tags(tags_json),
        confidence: confidence,
        source_session_id: source_session_id,
        source_detail: source_detail,
        usable_for_auto_decision: usable_for_auto_decision == 1,
        last_confirmed_at: last_confirmed_at,
        created_at: created_at
      }
    end)
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.list failed: #{Exception.message(e)}")
      []
  end

  @doc """
  Create a single knowledge entry manually.
  Accepts: type, content, tags, confidence, source_detail.
  Deduplicates via content_hash.
  """
  def create_entry(attrs) when is_map(attrs) do
    content = normalize_content(Map.get(attrs, "content", attrs[:content] || ""))
    type = normalize_type(Map.get(attrs, "type", attrs[:type] || "fact"))
    tags = normalize_tags(Map.get(attrs, "tags", attrs[:tags] || []))
    confidence = Map.get(attrs, "confidence", attrs[:confidence] || 0.5)
    source_detail = Map.get(attrs, "source_detail", attrs[:source_detail] || "manual")

    if content == "" do
      {:error, :empty_content}
    else
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      id = "mw-#{System.unique_integer([:positive])}"

      try do
        result =
          Ecto.Adapters.SQL.query!(
            AIBrain.Repo,
            """
            INSERT OR IGNORE INTO knowledge_entries
              (id, type, content, content_hash, tags, source_type, source_detail,
               confidence, decay_score, created_at, updated_at, last_confirmed_at)
            VALUES (?, ?, ?, ?, ?, 'manual', ?, ?, 1.0, ?, ?, ?)
            """,
            [
              id,
              type,
              content,
              content_hash,
              Jason.encode!(tags),
              source_detail,
              confidence,
              now,
              now,
              now
            ]
          )

        if result.num_rows == 1 do
          {:ok,
           %{
             id: id,
             type: type,
             content: content,
             tags: tags,
             confidence: confidence,
             source_detail: source_detail,
             usable_for_auto_decision: false,
             last_confirmed_at: now,
             created_at: now
           }}
        else
          {:error, :duplicate}
        end
      rescue
        e ->
          Logger.error("AIBrain.KnowledgeWiki.create_entry failed: #{Exception.message(e)}")
          {:error, :create_failed}
      end
    end
  end

  @doc "Delete a knowledge entry by ID."
  def delete(id) do
    Ecto.Adapters.SQL.query!(AIBrain.Repo, "DELETE FROM knowledge_entries WHERE id = ?", [id])
    :ok
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.delete failed: #{Exception.message(e)}")
      {:error, :not_found}
  end

  @doc "Update fields on a knowledge entry. Accepted keys: usable_for_auto_decision, source_detail, confidence."
  def update_entry(id, attrs) when is_map(attrs) do
    sets = []
    params = []

    {sets, params} =
      if Map.has_key?(attrs, "usable_for_auto_decision") or
           Map.has_key?(attrs, :usable_for_auto_decision) do
        val =
          Map.get(attrs, "usable_for_auto_decision", Map.get(attrs, :usable_for_auto_decision))

        {["usable_for_auto_decision = ?" | sets], [if(val, do: 1, else: 0) | params]}
      else
        {sets, params}
      end

    {sets, params} =
      if Map.has_key?(attrs, "source_detail") or Map.has_key?(attrs, :source_detail) do
        val = Map.get(attrs, "source_detail", Map.get(attrs, :source_detail))
        {["source_detail = ?" | sets], [val | params]}
      else
        {sets, params}
      end

    {sets, params} =
      if Map.has_key?(attrs, "confidence") or Map.has_key?(attrs, :confidence) do
        val = Map.get(attrs, "confidence", Map.get(attrs, :confidence))
        {["confidence = ?" | sets], [val | params]}
      else
        {sets, params}
      end

    if sets == [] do
      {:error, :no_fields_to_update}
    else
      set_clause = Enum.join(Enum.reverse(sets), ", ")
      params = Enum.reverse(params) ++ [id]

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "UPDATE knowledge_entries SET #{set_clause} WHERE id = ?",
        params
      )

      :ok
    end
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.update_entry failed: #{Exception.message(e)}")
      {:error, :update_failed}
  end

  @doc "Format knowledge entries as a string for system prompt injection."
  def format_for_prompt(entries) do
    if entries == [] do
      ""
    else
      lines =
        Enum.map(entries, fn entry ->
          "- [#{entry.type}] #{entry.content}"
        end)

      (["## Knowledge from previous sessions", ""] ++ lines)
      |> Enum.join("\n")
    end
  end

  # ── LLM-based extraction ─────────────────────────────────────

  defp try_llm_extraction(conversation_text) do
    router = AIBrain.Provider.Router

    case GenServer.call(router, {:select, "openai", nil}, 2000) do
      {:ok, provider} ->
        do_llm_extraction(provider, conversation_text)

      _ ->
        {:error, :no_provider}
    end
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.try_llm_extraction failed: #{Exception.message(e)}")
      {:error, :no_provider}
  catch
    _, _ -> {:error, :no_provider}
  end

  defp do_llm_extraction(provider, conversation_text) do
    system_prompt = """
    You are a knowledge distillation engine. Analyze the conversation below and extract
    structured knowledge entries. Return ONLY a JSON array. No markdown, no explanation.

    Each entry must be a JSON object with exactly these fields:
      "type": one of "fact", "preference", "learning", "task_outcome", "failure_pattern"
      "content": a concise, self-contained statement (max 200 chars)
      "tags": array of tag strings (max 3)

    Guidelines:
    - "fact": objective information about the user, project, or environment
    - "preference": user's stated preferences or recurring patterns
    - "learning": insights, solutions, or important realizations
    - "task_outcome": what was accomplished or attempted
    - "failure_pattern": things that went wrong, error patterns, approaches that failed,
      dead ends, common mistakes. Include the context and what was tried.

    IMPORTANT: Always extract failure_pattern entries when something went wrong or didn't work.
    These are crucial for avoiding repeated mistakes.

    Extract at most 5 entries. If nothing worth preserving, return an empty array.
    """

    messages = [
      %{role: "system", content: system_prompt},
      %{
        role: "user",
        content: "Extract knowledge from this conversation:\n\n#{conversation_text}"
      }
    ]

    case AIBrain.LLM.Client.stream(provider, messages, [],
           system: system_prompt,
           protocol: "openai",
           on_event: fn _ -> :ok end
         ) do
      {:ok, :streaming_complete} ->
        response = collect_response()
        Jason.decode(response)

      _ ->
        {:error, :llm_failed}
    end
  end

  defp collect_response(acc \\ "") do
    receive do
      {:sse_event, {:text_delta, text}} -> collect_response(acc <> text)
      {:sse_event, {:stop, _reason}} -> acc
      {:sse_done} -> acc
    after
      30_000 -> acc
    end
  end

  # ── Fallback extraction ──────────────────────────────────────

  defp fallback_extraction(turns) do
    turns
    |> Enum.flat_map(fn turn ->
      user_msg = Map.get(turn, "user_message", "") || ""
      asst_resp = Map.get(turn, "assistant_response", "") || ""
      combined = user_msg <> " " <> asst_resp

      extract_facts_from_text(combined) ++ extract_preferences_from_text(combined)
    end)
    |> Enum.uniq_by(&String.downcase(&1.content))
    |> Enum.take(5)
  end

  defp extract_facts_from_text(text) do
    # Simple heuristic: look for "I am", "my name", declarative statements
    facts = []

    facts =
      case Regex.run(~r/my name is (\w+)/i, text) do
        [_, name] ->
          [
            %{type: "fact", content: "User's name is #{name}", tags: ["user"], confidence: 0.8}
            | facts
          ]

        nil ->
          facts
      end

    facts =
      case Regex.run(~r/I (?:work|am) (?:at|a|an) (.+?)(?:\.|,|$)/i, text) do
        [_, role] ->
          [
            %{
              type: "fact",
              content: "User is #{String.trim(role)}",
              tags: ["user"],
              confidence: 0.6
            }
            | facts
          ]

        nil ->
          facts
      end

    facts
  end

  defp extract_preferences_from_text(text) do
    prefs = []

    prefs =
      case Regex.run(~r/I (?:prefer|like|love|enjoy) (.+?)(?:\.|,|$)/i, text) do
        [_, pref] ->
          [
            %{
              type: "preference",
              content: "User prefers #{String.trim(pref)}",
              tags: ["preference"],
              confidence: 0.5
            }
            | prefs
          ]

        nil ->
          prefs
      end

    prefs
  end

  # ── Persistence ──────────────────────────────────────────────

  defp persist_entries(entries, session_id) do
    Enum.reduce(entries, 0, fn entry, count ->
      content = normalize_content(Map.get(entry, "content", entry[:content] || ""))
      type = normalize_type(Map.get(entry, "type", entry[:type] || "fact"))
      tags = normalize_tags(Map.get(entry, "tags", entry[:tags] || []))
      confidence = Map.get(entry, "confidence", entry[:confidence] || 0.5)

      if content == "" do
        count
      else
        content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        try do
          result =
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
                content,
                content_hash,
                Jason.encode!(tags),
                session_id,
                confidence,
                now,
                now,
                now
              ]
            )

          if result.num_rows == 1 do
            generate_and_store_embedding(content_hash, content)
            count + 1
          else
            refresh_existing_entry(content_hash, confidence, now)
            count
          end
        rescue
          e ->
            Logger.error(
              "AIBrain.KnowledgeWiki.persist_entries failed to store entry: #{Exception.message(e)}"
            )

            count
        end
      end
    end)
  end

  defp normalize_content(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 500)
  end

  defp normalize_content(_), do: ""

  defp normalize_type(type) when type in ["fact", "preference", "learning", "task_outcome"],
    do: type

  defp normalize_type(type) when type in [:fact, :preference, :learning, :task_outcome],
    do: Atom.to_string(type)

  defp normalize_type(_), do: "fact"

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp normalize_tags(_), do: []

  defp refresh_existing_entry(content_hash, confidence, now) do
    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      """
      UPDATE knowledge_entries
      SET confidence = MAX(confidence, ?), last_confirmed_at = ?
      WHERE content_hash = ?
      """,
      [confidence, now, content_hash]
    )
  rescue
    e ->
      Logger.error("AIBrain.KnowledgeWiki.refresh_existing_entry failed: #{Exception.message(e)}")
      :ok
  end

  defp generate_and_store_embedding(content_hash, content) do
    case AIBrain.Embeddings.embed(content) do
      {:ok, vector} ->
        blob = AIBrain.Embeddings.encode_blob(vector)

        Ecto.Adapters.SQL.query!(
          AIBrain.Repo,
          "UPDATE knowledge_entries SET embedding = ? WHERE content_hash = ?",
          [blob, content_hash]
        )

      {:error, :not_configured} ->
        # No embedding service configured, skip
        :ok

      {:error, reason} ->
        Logger.warning("KnowledgeWiki: embedding failed for #{content_hash}: #{inspect(reason)}")
    end
  end

  defp update_session_notes(session_id, entries) do
    # Build a brief summary from the entries
    summaries =
      entries
      |> Enum.map(fn
        %{type: type, content: content} -> "[#{type}] #{content}"
        %{"type" => type, "content" => content} -> "[#{type}] #{content}"
      end)
      |> Enum.join("; ")

    if summaries != "" do
      try do
        Ecto.Adapters.SQL.query!(
          AIBrain.Repo,
          "UPDATE sessions SET notes = ? WHERE id = ?",
          [summaries, session_id]
        )
      rescue
        e ->
          Logger.error(
            "AIBrain.KnowledgeWiki.update_session_notes failed: #{Exception.message(e)}"
          )

          :ok
      end
    end
  end

  # ── Query helpers ────────────────────────────────────────────

  defp build_where_clauses(nil), do: {[], []}

  defp build_where_clauses(type) do
    if is_nil(type) do
      {[], []}
    else
      {["type = ?"], [type]}
    end
  end

  @doc """
  Apply temporal decay to all knowledge entries.

  Decay halves the decay_score every 30 days since last_confirmed_at.
  Called periodically by the DB maintenance process.
  Returns the number of entries decayed.
  """
  def apply_decay do
    now = DateTime.utc_now()

    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id, decay_score, last_confirmed_at FROM knowledge_entries WHERE decay_score > 0.01",
        []
      )

    count =
      Enum.reduce(result.rows, 0, fn [id, current_score, last_confirmed_at], acc ->
        case DateTime.from_iso8601(last_confirmed_at) do
          {:ok, confirmed, _} ->
            days_elapsed = DateTime.diff(now, confirmed, :day)
            # Halve every 30 days (use integer division for halving count)
            halvings = div(days_elapsed, 30)
            new_score = current_score * :math.pow(0.5, halvings)
            new_score = Float.round(new_score, 4)

            if new_score < current_score - 0.001 do
              Ecto.Adapters.SQL.query!(
                AIBrain.Repo,
                "UPDATE knowledge_entries SET decay_score = ? WHERE id = ?",
                [new_score, id]
              )

              acc + 1
            else
              acc
            end

          _ ->
            acc
        end
      end)

    Logger.info("KnowledgeWiki: decayed #{count} entries")
    count
  rescue
    e ->
      Logger.error("KnowledgeWiki.apply_decay failed: #{Exception.message(e)}")
      0
  end

  defp rank_by_relevance(entries, query) do
    # Try vector-based ranking if embeddings are available
    has_vectors = Enum.any?(entries, & &1.embedding)

    if has_vectors do
      rank_by_vector(entries, query)
    else
      rank_by_keyword(entries, query)
    end
  end

  defp rank_by_keyword(entries, query) do
    query_lower = String.downcase(query)
    query_words = MapSet.new(String.split(query_lower))

    entries
    |> Enum.map(fn entry ->
      content_lower = String.downcase(entry.content)
      words = MapSet.new(String.split(content_lower))
      overlap = MapSet.intersection(query_words, words) |> MapSet.size()
      boost = if overlap > 0, do: overlap * 0.1, else: 0.0
      decay = Map.get(entry, :decay_score) || 1.0
      %{entry | confidence: (entry.confidence + boost) * decay}
    end)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  defp rank_by_vector(entries, query) do
    case AIBrain.Embeddings.embed(query) do
      {:ok, query_vector} ->
        entries
        |> Enum.map(fn entry ->
          similarity =
            if entry.embedding do
              stored = AIBrain.Embeddings.decode_blob(entry.embedding)
              AIBrain.Embeddings.cosine_similarity(query_vector, stored)
            else
              0.0
            end

          decay = Map.get(entry, :decay_score) || 1.0
          # Blend: 70% vector similarity + 30% base confidence, all multiplied by decay
          blended = (similarity * 0.7 + entry.confidence * 0.3) * decay
          Map.put(entry, :confidence, blended)
        end)
        |> Enum.sort_by(& &1.confidence, :desc)

      {:error, _} ->
        rank_by_keyword(entries, query)
    end
  end

  defp decode_tags(nil), do: []

  defp decode_tags(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, tags} when is_list(tags) -> tags
      _ -> []
    end
  end

  defp decode_tags(_), do: []

  defp format_conversation(turns) do
    turns
    |> Enum.sort_by(& &1["turn"])
    |> Enum.map(fn turn ->
      user = Map.get(turn, "user_message", "") || ""
      asst = Map.get(turn, "assistant_response", "") || ""

      [maybe_line(user != "", "User: #{user}"), maybe_line(asst != "", "Assistant: #{asst}")]
      |> List.flatten()
      |> Enum.join("\n")
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n---\n")
  end

  defp maybe_line(true, text), do: [text]
  defp maybe_line(false, _text), do: []
end
