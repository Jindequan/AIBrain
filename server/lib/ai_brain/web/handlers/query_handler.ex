defmodule AIBrain.Web.Handlers.QueryHandler do
  @moduledoc """
  查询处理器 - 核心查询 API
  """

  require Logger
  import Plug.Conn
  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Session.HistoryMerge

  @doc """
  处理标准查询请求
  """
  def handle_query(conn, params) do
    with {:ok, messages} <- extract_messages(params),
         {:ok, opts} <- build_opts(params) do
      with_session_lock(opts, fn ->
        execution_messages = persist_and_load_execution_messages(messages, opts)

        Orchestrator.run_messages_auto(
          execution_messages,
          Keyword.put(opts, :_history_loaded, true),
          run_request(params, execution_messages, opts)
        )
      end)
      |> send_query_result(conn, opts)
    else
      {:error, reason} ->
        json_response(conn, 400, %{
          success: false,
          error: reason,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })
    end
  end

  @doc """
  处理流式查询 (SSE)
  """
  def handle_stream_query(conn, params) do
    with {:ok, messages} <- extract_messages(params),
         {:ok, opts} <- build_opts(params) do
      case try_session_lock(opts) do
        {:error, :already_running} ->
          json_response(conn, 409, %{success: false, error: "Session is currently running"})

        :ok ->
          try do
            # 在进入查询流程前，先持久化新增用户消息到 session store。
            execution_messages = persist_and_load_execution_messages(messages, opts)

            conn =
              conn
              |> put_resp_content_type("text/event-stream")
              |> put_resp_header("cache-control", "no-cache")
              |> put_resp_header("x-accel-buffering", "no")
              |> send_chunked(200)

            # 发送初始事件
            conn =
              case Plug.Conn.chunk(conn, "event: start\ndata: #{json(%{status: "started"})}\n\n") do
                {:ok, conn} -> conn
                {:error, _} -> conn
              end

            # 设置事件回调
            on_event = fn event ->
              data =
                json(%{
                  type: Map.get(event, :type, "event"),
                  timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
                  data: Map.delete(event, :__struct__)
                })

              Plug.Conn.chunk(conn, "event: message\ndata: #{data}\n\n")
            end

            opts = Keyword.put(opts, :on_event, on_event)

            # 运行查询
            case Orchestrator.run_messages_auto(
                   execution_messages,
                   Keyword.put(opts, :_history_loaded, true),
                   run_request(params, execution_messages, opts)
                 ) do
              {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
                Plug.Conn.chunk(
                  conn,
                  "event: complete\ndata: #{json(%{run_id: run_id, response: text})}\n\n"
                )

              {:ok, %{run_id: run_id, result: {:suspended, meta}}} ->
                Plug.Conn.chunk(
                  conn,
                  "event: suspended\ndata: #{json(%{run_id: run_id, suspended: true, reason: Map.get(meta, :reason, "approval_required"), status: Map.get(meta, :status, "waiting_approval"), approval_id: Map.get(meta, :approval_id) || Map.get(meta, :interaction_id), interaction_id: Map.get(meta, :interaction_id), tool_name: Map.get(meta, :tool_name)})}\n\n"
                )

              {:ok, %{run_id: run_id, result: {:error, reason}}} ->
                Logger.error("Stream query error: #{inspect(reason)}")

                Plug.Conn.chunk(
                  conn,
                  "event: error\ndata: #{json(%{run_id: run_id, error: "Internal server error"})}\n\n"
                )

              {:ok, %{run_id: run_id, result: {:error, reason, _detail}}} ->
                Logger.error("Stream query error: #{inspect(reason)}")

                Plug.Conn.chunk(
                  conn,
                  "event: error\ndata: #{json(%{run_id: run_id, error: "Service temporarily unavailable"})}\n\n"
                )

              {:error, reason} ->
                Logger.error("Stream query runtime error: #{inspect(reason)}")

                Plug.Conn.chunk(
                  conn,
                  "event: error\ndata: #{json(%{error: "Internal server error"})}\n\n"
                )
            end

            conn
          after
            unlock_session(opts)
          end
      end
    else
      {:error, reason} ->
        json_response(conn, 400, %{error: reason})
    end
  end

  # 私有函数

  defp extract_messages(%{"messages" => messages}) when is_list(messages) do
    normalized = Enum.map(messages, &normalize_message/1)
    {:ok, normalized}
  end

  defp extract_messages(%{"message" => message}) when is_binary(message) do
    {:ok, [AIBrain.Message.from_json(%{"role" => "user", "content" => message})]}
  end

  defp extract_messages(_) do
    {:error, "Invalid messages format. Expected 'messages' array or 'message' string"}
  end

  defp normalize_message(msg) when is_map(msg), do: AIBrain.Message.from_json(msg)

  defp normalize_message(msg) when is_binary(msg),
    do: AIBrain.Message.from_json(%{"role" => "user", "content" => msg})

  defp build_opts(params) do
    opts = [
      session_store: AIBrain.Config.session_store(),
      mode: Map.get(params, "mode", "approval_required"),
      permission_mode: :approval_required,
      run_policy: :always
    ]

    opts =
      case Map.get(params, "model") do
        model when is_binary(model) and model != "" -> Keyword.put(opts, :model, model)
        _ -> opts
      end

    # 添加可选参数
    opts =
      if session_id = Map.get(params, "session_id") do
        Keyword.put(opts, :session_id, session_id)
      else
        opts
      end

    opts =
      case Map.get(params, "workspace_path") do
        path when is_binary(path) and path != "" -> Keyword.put(opts, :workspace_path, path)
        _ -> opts
      end

    opts =
      case Map.get(params, "autonomy_level") do
        level when is_integer(level) -> Keyword.put(opts, :autonomy_level, level)
        level when is_binary(level) ->
          case Integer.parse(level) do
            {int, _} -> Keyword.put(opts, :autonomy_level, int)
            :error -> opts
          end

        _ ->
          opts
      end

    # 项目关联参数
    opts =
      if project_id = Map.get(params, "project_id") do
        opts
        |> Keyword.put(:project_id, project_id)
        |> Keyword.put(:plan_id, Map.get(params, "plan_id"))
        |> Keyword.put(:step_id, Map.get(params, "step_id"))
      else
        opts
      end

    {:ok, opts}
  end

  defp run_request(params, messages, opts) do
    session_id = Keyword.get(opts, :session_id)
    workspace_path = Keyword.get(opts, :workspace_path)

    metadata =
      params
      |> Map.get("metadata", %{})
      |> case do
        value when is_map(value) -> value
        _ -> %{}
      end

    %{
      source_type: "chat",
      source_id: session_id || Map.get(params, "source_id"),
      objective: latest_user_text(messages) || "User query",
      title: Map.get(params, "title"),
      mode: Map.get(params, "run_mode", "interactive"),
      autonomy_level: Map.get(params, "autonomy_level", 0),
      goal_id: Map.get(params, "goal_id"),
      session_id: session_id,
      thread_id: session_id,
      workspace_path: workspace_path,
      messages: messages,
      metadata: Map.put(metadata, "entrypoint", "api.query"),
      opts: opts
    }
  end

  defp with_session_lock(opts, fun) when is_function(fun, 0) do
    case try_session_lock(opts) do
      :ok ->
        try do
          fun.()
        after
          unlock_session(opts)
        end

      {:error, :already_running} ->
        {:error, :session_running}
    end
  end

  defp try_session_lock(opts) do
    session_id = Keyword.get(opts, :session_id)

    if is_binary(session_id) and session_id != "" do
      AIBrain.Session.Registry.try_register(session_id, self())
    else
      :ok
    end
  end

  defp unlock_session(opts) do
    session_id = Keyword.get(opts, :session_id)

    if is_binary(session_id) and session_id != "" do
      AIBrain.Session.Registry.unregister(session_id)
    end
  end

  defp send_query_result(result, conn, opts) do
    case result do
      {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
        maybe_enqueue_distillation(opts)

        json_response(conn, 200, %{
          success: true,
          run_id: run_id,
          response: text,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:ok, %{run_id: run_id, result: {:suspended, meta}}} ->
        maybe_enqueue_distillation(opts)

        json_response(conn, 202, %{
          success: false,
          run_id: run_id,
          suspended: true,
          reason: Map.get(meta, :reason, "approval_required"),
          status: Map.get(meta, :status, "waiting_approval"),
          approval_id: Map.get(meta, :approval_id) || Map.get(meta, :interaction_id),
          interaction_id: Map.get(meta, :interaction_id),
          tool_name: Map.get(meta, :tool_name),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:ok, %{run_id: run_id, result: {:error, reason}}} ->
        Logger.error("Query error: #{inspect(reason)}")

        json_response(conn, 500, %{
          success: false,
          run_id: run_id,
          error: "Internal server error",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:ok, %{run_id: run_id, result: {:error, reason, _detail}}} ->
        Logger.error("Query error: #{inspect(reason)}")

        json_response(conn, 503, %{
          success: false,
          run_id: run_id,
          error: "Service temporarily unavailable",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:error, :session_running} ->
        json_response(conn, 409, %{success: false, error: "Session is currently running"})

      {:error, reason} ->
        Logger.error("Query runtime error: #{inspect(reason)}")

        json_response(conn, 500, %{
          success: false,
          error: "Internal server error",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })
    end
  end

  defp latest_user_text(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "user", content: content} when is_binary(content) ->
        content

      %{role: "user", content: content} when is_list(content) ->
        Enum.find_value(content, fn
          %{"type" => "text", "text" => text} -> text
          %{type: "text", text: text} -> text
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  # 在进入查询流程前持久化新增用户消息，然后使用完整 session 历史执行。
  # 这样 WS/SSE/REST 三条 chat 入口的上下文行为保持一致。
  defp persist_and_load_execution_messages(messages, opts) do
    session_id = Keyword.get(opts, :session_id)

    if session_id do
      store = AIBrain.Config.session_store()
      existing_messages = load_existing_messages(store, session_id)

      messages
      |> new_messages_for_session(existing_messages)
      |> Enum.each(fn msg ->
        case store.append_message(store, session_id, msg) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error(
              "SSE: failed to persist user message for #{session_id}: #{inspect(reason)}"
            )
        end
      end)

      case store.load_session(store, session_id) do
        {:ok, session} -> session.messages
        {:error, _} -> messages
      end
    else
      messages
    end
  end

  defp load_existing_messages(store, session_id) do
    case store.load_session(store, session_id) do
      {:ok, session} when is_list(session.messages) -> session.messages
      _ -> []
    end
  end

  defp new_messages_for_session(incoming, existing)
       when is_list(incoming) and is_list(existing) do
    existing
    |> HistoryMerge.merge(incoming)
    |> Enum.drop(length(existing))
    |> Enum.filter(&user_message?/1)
  end

  defp user_message?(%{role: "user"}), do: true
  defp user_message?(%{"role" => "user"}), do: true
  defp user_message?(%AIBrain.Message{role: "user"}), do: true
  defp user_message?(_), do: false

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp maybe_enqueue_distillation(opts) do
    session_id = Keyword.get(opts, :session_id)

    if is_binary(session_id) and session_id != "" do
      AIBrain.Memory.Distiller.enqueue(session_id)
    end
  end

  defp json(data), do: Jason.encode!(data)
end
