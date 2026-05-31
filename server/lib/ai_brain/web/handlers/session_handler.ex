defmodule AIBrain.Web.Handlers.SessionHandler do
  @moduledoc """
  Session HTTP handler - clean functional style.

  ## Responsibilities

  - HTTP request handling ONLY
  - No business logic (delegates to Request/Response)
  - No streaming logic (delegate to Streamer)

  ## Before vs After

  ### BEFORE (stinking mess):
  ```elixir
  def handle_create_session(conn, params) do
    messages = Map.get(params, "messages", [])
    model = Map.get(params, "model", ...)
    mode = Map.get(params, "mode", "default")
    # ... 20+ more Map.get calls ...
    # ... business logic mixed with HTTP ...
  end
  ```

  ### AFTER (clean functional):
  ```elixir
  def handle_create_session(conn, params) do
    request = Request.build_from_params(params)

    case Request.validate(request, :create) do
      :ok -> create_session(conn, request)
      {:error, reason} -> Response.bad_request(conn, reason)
    end
  end
  ```
  """

  require Logger

  alias AIBrain.Web.Handlers.{Session.Request, Session.Response}
  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Session.Store

  @doc """
  Get session details.
  """
  def handle_get_session(conn, session_id) do
    include_messages = include_messages?(conn)

    case load_session_for_get(session_id, include_messages) do
      {:ok, session} ->
        data = build_session_data(session, include_messages: include_messages)

        Response.success(200, data)
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.session_not_found(session_id)
        |> Response.send_json(conn)

      {:error, _reason} ->
        Response.internal_error("Failed to load session")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Paginated message loading for a session.

  GET /api/v1/sessions/:id/messages?limit=50&before=100

  - `limit` — number of messages to return (default 50, max 200)
  - `before` — 0-based index; load messages before this position
  """
  def handle_get_messages(conn, session_id) do
    limit = min(conn.params["limit"] |> parse_int() || 50, 200)
    before = conn.params["before"] |> parse_int()

    case AIBrain.ConversationLog.load_paginated(session_id, limit: limit, before: before) do
      {:ok, %{messages: messages, total: total, has_more: has_more}} ->
        Response.success(200, %{
          messages: Enum.map(messages, &serialize_message/1),
          total: total,
          has_more: has_more
        })
        |> Response.send_json(conn)

      {:error, reason} ->
        Response.internal_error("Failed to load messages: #{inspect(reason)}")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Create new session.
  """
  def handle_create_session(conn, params) do
    request = Request.build_from_params(params)

    case Request.validate(request, :create) do
      :ok ->
        create_session(conn, request)

      {:error, :no_messages} ->
        Response.bad_request("messages required")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Send message to session.
  """
  def handle_send_message(conn, session_id, params) do
    request = Request.build_for_resume(session_id, params)

    case Request.validate(request, :send_message) do
      :ok ->
        with_session_execution(conn, session_id, fn ->
          append_messages(session_id, request.messages)
          stream_response(conn, session_id, request)
        end)

      {:error, :no_messages} ->
        Response.bad_request("message or messages required")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Resume session (sync API).
  """
  def handle_resume_session(conn, session_id, params) do
    request = Request.build_for_resume(session_id, params)

    case Request.validate(request, :resume) do
      :ok ->
        with_session_execution(conn, session_id, fn ->
          append_messages(session_id, request.messages)
          execute_query(conn, session_id, request)
        end)

      {:error, :no_messages} ->
        # Resume without new messages is OK
        with_session_execution(conn, session_id, fn ->
          execute_query(conn, session_id, request)
        end)
    end
  end

  @doc """
  Update session.
  """
  def handle_update_session(conn, session_id, params) do
    request = Request.build_for_update(session_id, params)

    case Request.validate(request, :update) do
      :ok ->
        update_session(conn, session_id, request)

      {:error, :invalid_update} ->
        Response.bad_request("title or workspace_path required")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Delete session.
  """
  def handle_delete_session(conn, session_id) do
    case store().delete_session(store(), session_id) do
      :ok ->
        Response.success(200, %{message: "Session deleted", session_id: session_id})
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.session_not_found(session_id)
        |> Response.send_json(conn)

      {:error, _reason} ->
        Response.internal_error("Failed to delete session")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Stop a running session.
  """
  def handle_stop_session(conn, session_id) do
    case AIBrain.Session.Registry.abort(session_id) do
      :ok ->
        Response.success(200, %{status: "stopped", session_id: session_id})
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.success(200, %{status: "not_running", session_id: session_id})
        |> Response.send_json(conn)

      {:error, :already_dead} ->
        Response.success(200, %{status: "not_running", session_id: session_id})
        |> Response.send_json(conn)
    end
  end

  @doc """
  Delete message.
  """
  def handle_delete_message(conn, session_id, message_id) do
    case store().delete_message(store(), session_id, message_id) do
      :ok ->
        Response.success(200, %{
          success: true,
          message: "Message deleted",
          message_id: message_id
        })
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.error(404, "Session or message not found")
        |> Map.put(:data, %{session_id: session_id, message_id: message_id})
        |> Response.send_json(conn)

      {:error, _reason} ->
        Response.internal_error("Failed to delete message")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Truncate session history before resending from an edited message.
  """
  def handle_truncate_messages(conn, session_id, params) do
    from_index = Map.get(params, "from_index") |> parse_int()

    cond do
      is_nil(from_index) or from_index < 0 ->
        Response.bad_request("from_index must be a non-negative integer")
        |> Response.send_json(conn)

      true ->
        case store().truncate_messages(store(), session_id, from_index) do
          {:ok, result} ->
            Response.success(200, Map.merge(%{success: true, session_id: session_id}, result))
            |> Response.send_json(conn)

          {:error, :not_found} ->
            Response.session_not_found(session_id)
            |> Response.send_json(conn)

          {:error, _reason} ->
            Response.internal_error("Failed to truncate messages")
            |> Response.send_json(conn)
        end
    end
  end

  @doc """
  Search session history.
  """
  def handle_search(conn, session_id) do
    request = Request.build_for_search(session_id, conn.params)

    case Request.validate(request, :search) do
      :ok ->
        matches = search_all_segments(session_id, request.search_query)

        Response.success(200, %{
          query: request.search_query,
          session_id: session_id,
          matches: matches,
          total: length(matches)
        })
        |> Response.send_json(conn)

      {:error, :missing_query} ->
        Response.bad_request("missing query parameter q")
        |> Response.send_json(conn)
    end
  end

  # ── Session Operations ───────────────────────────────────────────

  defp create_session(conn, %Request{} = request) do
    store_opts = Request.to_store_opts(request)
    {session_id, _status} = Store.find_or_create_session!(store(), store_opts)

    if length(request.messages) > 0 do
      :ok = append_messages(session_id, request.messages)
      stream_response(conn, session_id, request)
    else
      title = derive_title(request.messages)

      Response.success(201, %{
        session_id: session_id,
        title: title,
        messages: [],
        model: request.model,
        workspace_path: request.workspace_path
      })
      |> Response.send_json(conn)
    end
  end

  defp update_session(conn, session_id, %Request{} = request) do
    cond do
      is_binary(request.title) and String.trim(request.title) != "" ->
        store().update_title(store(), session_id, String.trim(request.title))

        Response.success(200, %{session_id: session_id, title: String.trim(request.title)})
        |> Response.send_json(conn)

      is_binary(request.workspace_path) ->
        path =
          if String.trim(request.workspace_path) == "",
            do: nil,
            else: String.trim(request.workspace_path)

        store().update_workspace_path(store(), session_id, path)

        Response.success(200, %{session_id: session_id, workspace_path: path})
        |> Response.send_json(conn)

      true ->
        Response.bad_request("title or workspace_path required")
        |> Response.send_json(conn)
    end
  end

  defp execute_query(conn, session_id, %Request{} = request) do
    opts = Request.to_runtime_opts(request, store())

    case Orchestrator.resume_session_auto(session_id, opts) do
      {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
        Response.success(200, %{
          success: true,
          response: text,
          session_id: session_id,
          run_id: run_id
        })
        |> Response.send_json(conn)

      {:ok, %{run_id: run_id, result: {:suspended, meta}}} ->
        Response.success(202, %{
          success: false,
          suspended: true,
          session_id: session_id,
          run_id: run_id,
          status: Map.get(meta, :status, "waiting_approval"),
          reason: Map.get(meta, :reason, "approval_required"),
          approval_id: Map.get(meta, :approval_id) || Map.get(meta, :interaction_id),
          interaction_id: Map.get(meta, :interaction_id),
          tool_name: Map.get(meta, :tool_name)
        })
        |> Response.send_json(conn)

      {:error, :session_not_found} ->
        Response.session_not_found(session_id)
        |> Response.send_json(conn)

      {:ok, %{result: {:error, _reason}}} ->
        Response.internal_error("Query failed")
        |> Response.send_json(conn)

      {:ok, %{result: {:error, _reason, _detail}}} ->
        Response.internal_error("Query failed")
        |> Response.send_json(conn)

      {:error, _reason} ->
        Response.internal_error("Query failed")
        |> Response.send_json(conn)
    end
  end

  # ── Streaming ───────────────────────────────────────────────────

  defp stream_response(conn, session_id, %Request{} = request) do
    # Delegate to streaming module
    AIBrain.Web.Handlers.SessionStreamer.stream(conn, session_id, request)
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp store, do: AIBrain.Config.session_store()

  defp session_runtime_status(session_id) do
    case Process.whereis(AIBrain.Session.Registry) do
      nil ->
        "idle"

      _ ->
        if AIBrain.Session.Registry.is_running?(session_id), do: "running", else: "idle"
    end
  end

  defp load_session(session_id) do
    store().load_session(store(), session_id)
  end

  defp include_messages?(conn) do
    case conn.params["include_messages"] do
      "true" -> true
      "1" -> true
      true -> true
      _ -> false
    end
  end

  defp load_session_for_get(session_id, true), do: load_session(session_id)

  defp load_session_for_get(session_id, false) do
    s = store()

    if function_exported?(s, :load_session_head, 2) do
      case s.load_session_head(s, session_id) do
        {:ok, _} = ok -> ok
        {:error, _} -> load_session(session_id)
      end
    else
      load_session(session_id)
    end
  end

  defp build_session_data(session, opts) do
    include_messages = Keyword.get(opts, :include_messages, true)
    log_path = AIBrain.ConversationLog.log_file_path(session.session_id)

    goal_id = get_in(session, [:metadata, :goal_id]) || get_in(session, [:metadata, "goal_id"])

    message_count =
      Map.get(session, :message_count) ||
        Map.get(session, "message_count") ||
        length(Map.get(session, :messages, []))

    base = %{
      session_id: session.session_id,
      title: Map.get(session, :title),
      summary: Map.get(session, :summary),
      message_count: message_count,
      conversation_log_path: log_path,
      requested_model: get_in(session, [:metadata, :requested_model]),
      workspace_path: Map.get(session, :workspace_path),
      goal_id: goal_id,
      metadata: session.metadata,
      status: session_runtime_status(session.session_id)
    }

    if include_messages do
      Map.put(base, :messages, Map.get(session, :messages, []))
    else
      base
    end
  end

  defp append_messages(session_id, messages) do
    normalized = Enum.map(messages, &normalize/1)
    Enum.each(normalized, fn msg -> store().append_message(store(), session_id, msg) end)
  end

  defp derive_title(messages) do
    AIBrain.Session.Store.derive_title(messages)
  end

  defp with_session_execution(conn, session_id, fun) when is_function(fun, 0) do
    case load_session(session_id) do
      {:error, :not_found} ->
        Response.session_not_found(session_id)
        |> Response.send_json(conn)

      {:error, _reason} ->
        Response.internal_error("Internal error")
        |> Response.send_json(conn)

      {:ok, _session} ->
        case AIBrain.Session.Registry.try_register(session_id, self()) do
          :ok ->
            try do
              fun.()
            after
              AIBrain.Session.Registry.unregister(session_id)
            end

          {:error, :already_running} ->
            Response.error(409, "Session is currently running")
            |> Map.put(:data, %{session_id: session_id})
            |> Response.send_json(conn)
        end
    end
  end

  # ── Search ──────────────────────────────────────────────────────

  defp search_all_segments(session_id, query) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    session_dir = Path.join([data_dir, "sessions", session_id])

    current = Path.join(session_dir, "conversation.jsonl")
    archived = Path.wildcard(Path.join(session_dir, "conversation-*.jsonl"))
    all_files = [current | Enum.sort(archived)]

    all_files
    |> Enum.filter(&File.exists?/1)
    |> Enum.with_index()
    |> Enum.flat_map(fn {file, seg_idx} ->
      case search_jsonl_file(file, query, seg_idx) do
        nil -> []
        matches -> matches
      end
    end)
  end

  defp search_jsonl_file(file, query, seg_idx) do
    case File.read(file) do
      {:ok, content} ->
        messages =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(fn line ->
            case Jason.decode(line) do
              {:ok, msg} -> [msg]
              _ -> []
            end
          end)

        matches = search_messages(messages, query, seg_idx)
        if matches == [], do: nil, else: matches

      _ ->
        nil
    end
  end

  defp search_messages(messages, query, seg_idx) do
    messages
    |> Enum.with_index()
    |> Enum.flat_map(fn {msg, idx} ->
      texts = extract_searchable_text(msg)
      hits = Enum.filter(texts, &String.contains?(String.downcase(&1), query))

      if hits == [] do
        []
      else
        result = %{
          message_index: idx,
          role: msg["role"],
          hits: Enum.map(hits, &truncate_excerpt/1)
        }

        result = if seg_idx > 0, do: Map.put(result, :segment, seg_idx), else: result
        [result]
      end
    end)
  end

  defp extract_searchable_text(msg) do
    cond do
      is_binary(msg["content"]) ->
        [msg["content"]]

      is_list(msg["content"]) ->
        Enum.flat_map(msg["content"], fn block ->
          cond do
            block["type"] == "text" and is_binary(block["text"]) ->
              [block["text"]]

            block["type"] == "tool_use" ->
              texts = []
              texts = if is_binary(block["output"]), do: [block["output"] | texts], else: texts

              texts =
                if is_map(block["input"]), do: [inspect(block["input"]) | texts], else: texts

              texts

            block["type"] == "tool_result" and is_binary(block["content"]) ->
              [block["content"]]

            true ->
              []
          end
        end)

      true ->
        []
    end
  end

  defp truncate_excerpt(text, max_len \\ 120) do
    if byte_size(text) <= max_len do
      text
    else
      String.slice(text, 0, max_len) <> "..."
    end
  end

  # ── Message Normalization ─────────────────────────────────────────

  @doc false
  def normalize(%{"role" => "user", "content" => content}) when is_binary(content) do
    AIBrain.Message.from_json(%{"role" => "user", "content" => content})
  end

  def normalize(%{
        "role" => "user",
        "content" => [%{"type" => "tool_result", "tool_use_id" => tool_id, "content" => content}]
      }) do
    AIBrain.Message.new("tool",
      content: [%{type: "tool_result", tool_use_id: tool_id, content: content}]
    )
  end

  def normalize(%{"role" => "assistant", "content" => content}) when is_list(content) do
    AIBrain.Message.from_json(%{"role" => "assistant", "content" => content})
  end

  def normalize(%{"role" => role, "blocks" => blocks}) when is_list(blocks) do
    AIBrain.Message.new(role, content: blocks)
  end

  def normalize(msg) when is_binary(msg) do
    AIBrain.Message.from_json(%{"role" => "user", "content" => msg})
  end

  def normalize(%{"role" => role, "content" => content}) when is_list(content) do
    AIBrain.Message.from_json(%{"role" => role, "content" => content})
  end

  def normalize(%{"role" => role, "content" => content}) when is_binary(content) do
    AIBrain.Message.from_json(%{"role" => role, "content" => content})
  end

  def normalize(msg) when is_map(msg), do: AIBrain.Message.from_json(msg)

  defp parse_int(nil), do: nil
  defp parse_int(v) when is_binary(v), do: Integer.parse(v) |> elem_or_nil()
  defp parse_int(v) when is_integer(v), do: v

  defp elem_or_nil({i, _}), do: i
  defp elem_or_nil(:error), do: nil

  defp serialize_message(%AIBrain.Message{} = msg) do
    %{
      id: msg.id,
      role: msg.role,
      content: msg.content,
      name: msg.name,
      metadata: msg.metadata,
      created_at: msg.created_at
    }
  end

  defp serialize_message(msg) when is_map(msg), do: msg
end
