defmodule AIBrain.Session.Store.SQLite do
  @moduledoc """
  SQLite-backed session store for durable persistence.

  Session metadata is stored in the `sessions` SQLite table.
  Messages are persisted to `~/.aibrain/sessions/<id>/conversation.jsonl`.

  ETS is ONLY used to cache transient runtime events (SSE fragments)
  during active LLM calls. All persistent data goes through SQLite or disk.
  """

  use GenServer
  require Logger

  @behaviour AIBrain.Session.Store

  alias AIBrain.Repo
  alias AIBrain.Session.ShortID

  @max_turns 200

  # ── Client API (SessionStore behaviour) ─────────────────────

  @impl true
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def start_session(server \\ __MODULE__, session_id, opts \\ []) do
    GenServer.call(server, {:start_session, session_id, opts})
  end

  @impl true
  def append_event(server \\ __MODULE__, session_id, event) do
    GenServer.call(server, {:append_event, session_id, event})
  end

  @impl true
  def append_message(server \\ __MODULE__, session_id, message) do
    GenServer.call(server, {:append_message, session_id, message})
  end

  @impl true
  @doc """
  Check if session has exceeded max turns and archive if needed.
  Always returns {:continue, session_id}.
  """
  def maybe_rotate(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:maybe_rotate, session_id})
  end

  @impl true
  def delete_message(server \\ __MODULE__, session_id, message_id) do
    GenServer.call(server, {:delete_message, session_id, message_id})
  end

  @impl true
  def truncate_messages(server \\ __MODULE__, session_id, from_index) do
    GenServer.call(server, {:truncate_messages, session_id, from_index})
  end

  @impl true
  def load_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:load_session, session_id})
  end

  @impl true
  def load_session_head(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:load_session_head, session_id})
  end

  @impl true
  def delete_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:delete_session, session_id})
  end

  @impl true
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions)
  end

  def update_title(server \\ __MODULE__, session_id, title) do
    GenServer.call(server, {:update_title, session_id, title})
  end

  @impl true
  def update_workspace_path(server \\ __MODULE__, session_id, path) do
    GenServer.call(server, {:update_workspace_path, session_id, path})
  end

  @impl true
  def resume_messages(server \\ __MODULE__, session_id) do
    case load_session(server, session_id) do
      {:error, :not_found} -> []
      {:ok, session} -> session.messages
    end
  end

  @impl true
  def flush_to_disk(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:flush_to_disk, session_id})
  end

  @impl true
  def find_session_by_isolation(server \\ __MODULE__, workspace_path, channel_adapter, channel_id) do
    GenServer.call(
      server,
      {:find_session_by_isolation, workspace_path, channel_adapter, channel_id}
    )
  end

  # ── GenServer Callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(__MODULE__, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}, {:continue, :reconcile_zombies}}
  end

  @impl true
  def handle_continue(:reconcile_zombies, state) do
    backfill_null_titles()

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_session, session_id, opts}, _from, state) do
    session_id = session_id || ShortID.session_id()
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    new_messages = Keyword.get(opts, :messages, [])
    metadata = Keyword.get(opts, :metadata, %{})
    workspace_path = Keyword.get(opts, :workspace_path)

    case load_session_from_db(session_id) do
      {:ok, existing} ->
        merged_metadata =
          existing.metadata
          |> Map.merge(metadata)
          |> Map.put(
            :requested_model,
            Keyword.get(opts, :requested_model) || existing.metadata[:requested_model]
          )

        title = Keyword.get(opts, :title) || existing.title

        session_for_db = %{
          session_id: session_id,
          title: title,
          workspace_path: workspace_path || existing.workspace_path,
          metadata: merged_metadata,
          created_at: existing.created_at || now,
          updated_at: now
        }

        log_persist_result("start_session", session_id, persist_session_meta(session_for_db))

      {:error, :not_found} ->
        title =
          Keyword.get(opts, :title) || AIBrain.Session.Store.derive_title(new_messages)

        session_for_db = %{
          session_id: session_id,
          title: title,
          workspace_path: workspace_path,
          metadata:
            metadata
            |> Map.put(:requested_model, Keyword.get(opts, :requested_model)),
          created_at: now,
          updated_at: now
        }

        log_persist_result("start_session", session_id, persist_session_meta(session_for_db))

        AIBrain.ConversationLog.save_messages(session_id, new_messages)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:append_event, session_id, event}, _from, state) do
    update_runtime_events(session_id, fn events -> events ++ [event] end)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:append_message, session_id, message}, _from, state) do
    message = assign_id_and_timestamp(message)

    # Save to conversation.jsonl only (single source of truth)
    case AIBrain.ConversationLog.append_message(session_id, message) do
      :ok ->
        db_title = load_title_from_db(session_id)

        new_title =
          AIBrain.Session.Store.derive_title_for_update(
            db_title || "New Session",
            [message]
          )

        if new_title != "New Session" and new_title != db_title do
          persist_session_updated(session_id, new_title)
        else
          persist_session_updated(session_id, nil)
        end

        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error(
          "AIBrain.Session.Store.SQLite append_message: failed for #{session_id}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:maybe_rotate, session_id}, _from, state) do
    case load_session_from_db(session_id) do
      {:ok, session} ->
        turn_count = session.metadata.turn_count || 0

        if turn_count >= @max_turns do
          archive_and_rotate(session_id)
          {:reply, {:continue, session_id}, state}
        else
          {:reply, {:continue, session_id}, state}
        end

      {:error, :not_found} ->
        {:reply, {:continue, session_id}, state}
    end
  end

  @impl true
  def handle_call({:delete_message, session_id, message_id}, _from, state) do
    case AIBrain.ConversationLog.load_conversation(session_id) do
      {:ok, messages, _log} ->
        updated_messages =
          Enum.filter(messages, fn msg ->
            Map.get(msg, :id) != message_id and Map.get(msg, "id") != message_id
          end)

        if length(updated_messages) == length(messages) do
          {:reply, {:error, :not_found}, state}
        else
          try do
            AIBrain.ConversationLog.save_messages(session_id, updated_messages)

            {:reply, :ok, state}
          rescue
            e ->
              Logger.error("AIBrain.Session.Store.SQLite delete_message: #{Exception.message(e)}")

              {:reply, {:error, :persist_failed}, state}
          end
        end

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:truncate_messages, session_id, from_index}, _from, state) do
    case AIBrain.ConversationLog.truncate_messages(session_id, from_index) do
      {:ok, result} -> {:reply, {:ok, result}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  rescue
    e ->
      Logger.error("AIBrain.Session.Store.SQLite truncate_messages: #{Exception.message(e)}")
      {:reply, {:error, :persist_failed}, state}
  end

  @impl true
  def handle_call({:update_title, session_id, title}, _from, state) do
    persist_session_updated(session_id, title)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update_workspace_path, session_id, path}, _from, state) do
    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "UPDATE sessions SET workspace_path = ? WHERE id = ?",
      [path, session_id]
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:find_session_by_isolation, workspace_path, channel_adapter, channel_id},
        _from,
        state
      ) do
    result =
      cond do
        is_binary(workspace_path) and workspace_path != "" ->
          Ecto.Adapters.SQL.query!(
            AIBrain.Repo,
            "SELECT id FROM sessions WHERE workspace_path = ? ORDER BY started_at DESC LIMIT 1",
            [workspace_path]
          )

        is_binary(channel_adapter) and is_binary(channel_id) and channel_adapter != "" and
            channel_id != "" ->
          Ecto.Adapters.SQL.query!(
            AIBrain.Repo,
            "SELECT id FROM sessions WHERE channel_adapter = ? AND channel_id = ? ORDER BY started_at DESC LIMIT 1",
            [channel_adapter, channel_id]
          )

        true ->
          nil
      end

    session_id =
      case result do
        nil -> nil
        %{rows: [[id | _]]} -> id
        _ -> nil
      end

    {:reply, if(session_id, do: {:ok, session_id}, else: {:error, :not_found}), state}
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.find_session_by_isolation failed: #{Exception.message(e)}"
      )

      {:reply, {:error, :not_found}, state}
  end

  @impl true
  def handle_call({:load_session, session_id}, _from, state) do
    case AIBrain.ConversationLog.load_conversation(session_id) do
      {:ok, messages, log} ->
        {session_workspace, persisted_title} =
          case load_session_from_db(session_id) do
            {:ok, session_meta} -> {session_meta.workspace_path, session_meta.title}
            _ -> {nil, nil}
          end

        title =
          if persisted_title && persisted_title != "New Session" do
            persisted_title
          else
            AIBrain.Session.Store.derive_title(messages)
          end

        session = %{
          session_id: session_id,
          title: title,
          workspace_path: session_workspace || log["workspace_path"],
          metadata: %{
            requested_model: log["requested_model"]
          },
          messages: messages,
          runtime_events: load_runtime_events(session_id),
          created_at: log["created_at"] || now_iso(),
          updated_at: log["updated_at"] || log["created_at"] || now_iso()
        }

        {:reply, {:ok, session}, state}

      {:error, :not_found} ->
        # Fallback: session may exist in DB but has no conversation log yet
        case load_session_from_db(session_id) do
          {:ok, session_meta} ->
            now = now_iso()

            fallback = %{
              session_id: session_id,
              title: session_meta.title || session_id,
              workspace_path: session_meta.workspace_path,
              metadata: session_meta.metadata || %{},
              messages: [],
              runtime_events: [],
              created_at: session_meta.created_at || now,
              updated_at: session_meta.updated_at || now
            }

            {:reply, {:ok, fallback}, state}

          _ ->
            {:reply, {:error, :not_found}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:load_session_head, session_id}, _from, state) do
    message_count = AIBrain.ConversationLog.message_count(session_id)
    log_meta = AIBrain.ConversationLog.session_meta(session_id)

    case load_session_from_db(session_id) do
      {:ok, db} ->
        title =
          if db.title && db.title != "New Session" do
            db.title
          else
            log_meta["title"] || db.title || "New Session"
          end

        session = %{
          session_id: session_id,
          title: title,
          workspace_path: db.workspace_path || log_meta["workspace_path"],
          metadata:
            (db.metadata || %{})
            |> Map.put(:requested_model, log_meta["requested_model"]),
          messages: [],
          message_count: message_count,
          runtime_events: [],
          created_at: db.created_at || log_meta["created_at"] || now_iso(),
          updated_at: log_meta["updated_at"] || db.updated_at || now_iso()
        }

        {:reply, {:ok, session}, state}

      {:error, :not_found} ->
        if message_count > 0 or map_size(log_meta) > 0 do
          session = %{
            session_id: session_id,
            title: log_meta["title"] || "New Session",
            workspace_path: log_meta["workspace_path"],
            metadata: %{requested_model: log_meta["requested_model"]},
            messages: [],
            message_count: message_count,
            runtime_events: [],
            created_at: log_meta["created_at"] || now_iso(),
            updated_at: log_meta["updated_at"] || log_meta["created_at"] || now_iso()
          }

          {:reply, {:ok, session}, state}
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sqlite_sessions =
      load_all_sessions_from_db()
      |> Map.new(fn s -> {s.session_id, s} end)

    seen_ids = MapSet.new(Map.keys(sqlite_sessions))
    disk_sessions = load_disk_sessions(seen_ids)

    result =
      Map.merge(
        sqlite_sessions,
        Map.new(disk_sessions, fn s -> {s.session_id, s} end)
      )
      |> Map.values()
      |> Enum.sort_by(&(Map.get(&1, :updated_at) || Map.get(&1, :created_at) || ""), :desc)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    :ets.delete(__MODULE__, session_id)

    transaction_result =
      Repo.transaction(fn ->
        # Each DELETE is wrapped individually so a missing table doesn't
        # roll back the entire transaction.
        safe_delete(
          "DELETE FROM knowledge_entries WHERE first_source_session_id = ? OR source_session_id = ?",
          [session_id, session_id]
        )

        safe_delete(
          "DELETE FROM run_steps WHERE run_id IN (SELECT id FROM runs WHERE source_type = 'session' AND source_id = ?)",
          [session_id]
        )

        safe_delete(
          "DELETE FROM run_context_refs WHERE run_id IN (SELECT id FROM runs WHERE source_type = 'session' AND source_id = ?)",
          [session_id]
        )

        safe_delete("DELETE FROM runs WHERE source_type = 'session' AND source_id = ?", [
          session_id
        ])

        safe_delete("DELETE FROM events WHERE session_id = ?", [session_id])
        safe_delete("DELETE FROM sessions WHERE id = ?", [session_id])

        delete_session_files(session_id)
        {:ok, :deleted}
      end)

    case transaction_result do
      {:ok, {:ok, :deleted}} ->
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to delete session #{session_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:flush_to_disk, session_id}, _from, state) do
    :ets.delete(__MODULE__, session_id)
    {:reply, :ok, state}
  end

  # ── Private Helpers ─────────────────────────────────────────

  defp backfill_null_titles do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id FROM sessions WHERE title IS NULL OR title = '' OR title = 'New Session'",
        []
      )

    backfilled =
      Enum.reduce(result.rows, 0, fn [session_id], acc ->
        case AIBrain.ConversationLog.load_conversation(session_id) do
          {:ok, messages, _meta} when messages != [] ->
            title = AIBrain.Session.Store.derive_title(messages)

            if title != "New Session" do
              Ecto.Adapters.SQL.query!(
                AIBrain.Repo,
                "UPDATE sessions SET title = ? WHERE id = ?",
                [title, session_id]
              )

              acc + 1
            else
              acc
            end

          _ ->
            acc
        end
      end)

    if backfilled > 0 do
      Logger.info("SessionStore: backfilled #{backfilled} null titles from conversation.jsonl")
    end
  rescue
    e ->
      Logger.warning("SessionStore: title backfill skipped: #{Exception.message(e)}")
  end

  defp update_runtime_events(session_id, fun) do
    events =
      case :ets.lookup(__MODULE__, session_id) do
        [{^session_id, %{runtime_events: existing}}] -> fun.(existing)
        [] -> fun.([])
      end

    :ets.insert(__MODULE__, {session_id, %{runtime_events: events}})
  end

  defp load_runtime_events(session_id) do
    case :ets.lookup(__MODULE__, session_id) do
      [{^session_id, %{runtime_events: events}}] -> events
      [] -> []
    end
  end

  defp load_title_from_db(session_id) do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT title FROM sessions WHERE id = ?",
        [session_id]
      )

    case result.rows do
      [[title]] -> title
      _ -> nil
    end
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.load_title_from_db failed: #{Exception.message(e)}"
      )

      nil
  end

  defp persist_session_meta(session) do
    sql = """
    INSERT OR REPLACE INTO sessions
      (id, session_type, title, channel_adapter, channel_id, turn_count, started_at, workspace_path, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    params = [
      session.session_id,
      Map.get(session.metadata, :session_type, "manual"),
      Map.get(session, :title),
      Map.get(session.metadata, :channel_adapter),
      Map.get(session.metadata, :channel_id),
      Map.get(session.metadata, :turn_count, 0),
      session.created_at,
      session.workspace_path,
      session.created_at,
      Map.get(session, :updated_at, session.created_at)
    ]

    Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.persist_session_meta failed: #{Exception.message(e)}"
      )

      {:error, Exception.message(e)}
  end

  defp persist_session_updated(session_id, title) do
    {sql, params} =
      if title do
        {"UPDATE sessions SET turn_count = turn_count + 1, title = ? WHERE id = ?",
         [title, session_id]}
      else
        {"UPDATE sessions SET turn_count = turn_count + 1 WHERE id = ?", [session_id]}
      end

    Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.persist_session_updated failed: #{Exception.message(e)}"
      )

      {:error, Exception.message(e)}
  end

  defp log_persist_result(_context, _session_id, :ok), do: :ok
  defp log_persist_result(_context, _session_id, %{num_rows: _}), do: :ok

  defp log_persist_result(context, session_id, {:error, reason}) do
    Logger.error(
      "AIBrain.Session.Store.SQLite.#{context} persist failed for #{session_id}: #{reason}"
    )
  end

  defp load_session_from_db(session_id) do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id, title, channel_adapter, channel_id, turn_count, started_at, workspace_path FROM sessions WHERE id = ?",
        [session_id]
      )

    case result.rows do
      [[id, title, channel_adapter, channel_id, turn_count, started_at, workspace_path]] ->
        {:ok,
         %{
           session_id: id,
           title: title,
           workspace_path: workspace_path,
           metadata: %{
             channel_adapter: channel_adapter,
             channel_id: channel_id,
             turn_count: turn_count || 0
           },
           created_at: started_at,
           updated_at: started_at
         }}

      _ ->
        {:error, :not_found}
    end
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.load_session_from_db failed: #{Exception.message(e)}"
      )

      {:error, :not_found}
  end

  defp load_all_sessions_from_db do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id, title, turn_count, started_at, workspace_path, channel_adapter, channel_id FROM sessions ORDER BY started_at DESC",
        []
      )

    Enum.map(result.rows, fn [
                               id,
                               title,
                               turn_count,
                               started_at,
                               workspace_path,
                               channel_adapter,
                               channel_id
                             ] ->
      %{
        session_id: id,
        title: title || "New Session",
        message_count: turn_count || 0,
        requested_model: nil,
        workspace_path: workspace_path,
        channel_adapter: channel_adapter,
        channel_id: channel_id,
        created_at: started_at,
        updated_at: started_at
      }
    end)
  rescue
    e ->
      Logger.error(
        "AIBrain.Session.Store.SQLite.load_all_sessions_from_db failed: #{Exception.message(e)}"
      )

      []
  end

  defp load_disk_sessions(exclude_ids) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    sessions_dir = Path.join(data_dir, "sessions")

    case File.ls(sessions_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.starts_with?(&1, "session-"))
        |> Enum.reject(&MapSet.member?(exclude_ids, &1))
        |> Enum.map(fn session_id ->
          jsonl_file = Path.join([sessions_dir, session_id, "conversation.jsonl"])

          if File.exists?(jsonl_file) do
            case AIBrain.ConversationLog.load_conversation(session_id) do
              {:ok, messages, meta} ->
                title = AIBrain.Session.Store.derive_title(messages)

                %{
                  session_id: session_id,
                  title: title,
                  message_count: length(messages),
                  requested_model: meta["requested_model"],
                  workspace_path: meta["workspace_path"],
                  created_at: meta["created_at"],
                  updated_at: meta["updated_at"] || meta["created_at"]
                }

              _ ->
                nil
            end
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp delete_session_files(session_id) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    session_dir = Path.join([data_dir, "sessions", session_id])

    case File.rm_rf(session_dir) do
      {:ok, _} ->
        :ok

      {:error, _reason, _paths} ->
        Logger.warning(
          "AIBrain.Session.Store.SQLite.delete_session_files failed for #{session_id}"
        )

        :ok
    end
  end

  defp assign_id_and_timestamp(message) do
    message =
      if is_nil(Map.get(message, :id)) do
        Map.put(message, :id, ShortID.message_id())
      else
        message
      end

    if is_nil(Map.get(message, :created_at)) do
      Map.put(message, :created_at, DateTime.utc_now() |> DateTime.to_iso8601())
    else
      message
    end
  end

  defp archive_and_rotate(session_id) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    session_dir = Path.join([data_dir, "sessions", session_id])
    log_file = Path.join(session_dir, "conversation.jsonl")

    archived_messages =
      if File.exists?(log_file) do
        case AIBrain.ConversationLog.load_conversation(session_id) do
          {:ok, messages, _meta} ->
            timestamp =
              DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:.]/, "-")

            archive_file = Path.join(session_dir, "conversation-#{timestamp}.jsonl")

            case File.rename(log_file, archive_file) do
              :ok ->
                Logger.info(
                  "Session #{session_id}: archived conversation to #{Path.basename(archive_file)}"
                )

                messages

              {:error, reason} ->
                Logger.error(
                  "Session #{session_id}: failed to archive conversation: #{inspect(reason)}"
                )

                []
            end

          _ ->
            Logger.warning("Session #{session_id}: failed to load conversation, starting fresh")
            []
        end
      else
        []
      end

    # Create fresh conversation.jsonl
    AIBrain.ConversationLog.save_messages(session_id, [])

    # Generate summary from archived messages and store as base_context
    if archived_messages != [] do
      summary = summarise_messages(archived_messages)
      AIBrain.ConversationLog.set_base_context(session_id, summary)
    end

    # Reset turn count in DB back to 0
    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "UPDATE sessions SET turn_count = 0 WHERE id = ?",
      [session_id]
    )

    Logger.info("Session #{session_id}: rotation complete, turn_count reset to 0")
  end

  defp summarise_messages(messages) do
    user_count = Enum.count(messages, &(&1["role"] == "user"))

    # Extract key content for the LLM prompt (limit to avoid token overflow)
    excerpts =
      messages
      |> Enum.take(-40)
      |> Enum.map(fn m ->
        role = m["role"] || "unknown"
        text = extract_text(m["content"])
        if text, do: "#{role}: #{String.slice(text, 0, 200)}", else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    prompt = """
    Summarize the following conversation in 2-3 concise paragraphs. Focus on:
    1. What the user was trying to accomplish
    2. What was discussed or decided
    3. Any important context, preferences, or outcomes that should carry forward

    Conversation (#{user_count} user messages total, showing last 40):
    #{excerpts}
    """

    case AIBrain.LLM.SimpleChat.call(prompt,
           system:
             "You are a conversation summarizer. Be concise and factual. Preserve specific names, URLs, file paths, and decisions."
         ) do
      {:ok, summary} when is_binary(summary) and byte_size(summary) > 10 ->
        Logger.info("Session rotation: generated semantic summary (#{byte_size(summary)} bytes)")
        summary

      _ ->
        Logger.warning("Session rotation: LLM summary failed, using fallback")
        fallback_summary(messages)
    end
  rescue
    e ->
      Logger.warning("Session rotation: summary generation error: #{Exception.message(e)}")
      fallback_summary(messages)
  end

  defp fallback_summary(messages) do
    user_count = Enum.count(messages, &(&1["role"] == "user"))
    assistant_count = Enum.count(messages, &(&1["role"] == "assistant"))

    first_user =
      Enum.find_value(messages, fn m ->
        if m["role"] == "user" do
          extract_text(m["content"])
        end
      end)

    "Previous conversation: #{user_count} user messages, #{assistant_count} assistant messages." <>
      if(first_user, do: " First topic: #{String.slice(first_user, 0, 200)}", else: "")
  end

  defp extract_text(content) when is_list(content) do
    Enum.find_value(content, fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{type: "text", text: text} when is_binary(text) -> text
      _ -> nil
    end)
  end

  defp extract_text(content) when is_binary(content), do: content
  defp extract_text(_), do: nil

  defp now_iso do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp safe_delete(sql, params) do
    Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)
  rescue
    e ->
      Logger.warning("SessionStore: skipping DELETE (missing table?): #{Exception.message(e)}")
      :ok
  end
end
