defmodule AIBrain.Web.Socket do
  @moduledoc """
  WebSocket 处理器 - 实时双向通信
  """

  @behaviour WebSock

  require Logger

  defp store,
    do: AIBrain.Config.session_store()

  @impl WebSock
  def init(_opts) do
    # Subscribe to background monitor notifications
    try do
      AIBrain.Monitor.subscribe()
    rescue
      e ->
        Logger.error(
          "AIBrain.Web.Socket.init failed to subscribe to monitor: #{Exception.message(e)}"
        )

        :ok
    end

    # Subscribe to global Bus events (scheduler, run, task, and interaction notifications).
    try do
      AIBrain.Channel.Bus.subscribe(self())
    rescue
      e ->
        Logger.error("Socket failed to subscribe to channel bus: #{Exception.message(e)}")
        :ok
    end

    {:ok, %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}}
  end

  @impl WebSock
  def handle_in({data, _opts}, state) do
    with {:ok, payload} <- Jason.decode(data) do
      # Protocol-level: heartbeat ping/pong
      if payload["type"] == "ping" do
        {:push, [{:text, Jason.encode!(%{type: "pong"})}], state}
      else
        case payload["type"] do
          "subscribe_run" ->
            handle_subscribe_run(payload, state)

          "unsubscribe_run" ->
            handle_unsubscribe_run(payload, state)

          # Query messages have no type field — they're sent with message/messages directly
          nil ->
            handle_query(payload, state)

          unknown ->
            Logger.warning("WebSocket: rejecting unknown message type #{inspect(unknown)}")
            error = Jason.encode!(%{type: "error", error: "Unknown message type: #{unknown}"})
            {:push, [{:text, error}], state}
        end
      end
    else
      {:error, _reason} ->
        error = Jason.encode!(%{type: "error", error: "Invalid JSON"})
        {:push, [{:text, error}], state}
    end
  end

  defp handle_query(payload, state) do
    with {:ok, messages} <- extract_messages(payload),
         {:ok, opts} <- build_opts(payload, state),
         {:ok, session_id} <- require_session_id(opts) do
      ws_pid = self()
      trace_id = Logger.metadata()[:trace_id]

      state =
        if !MapSet.member?(state.subscribed_sessions, session_id) do
          try do
            AIBrain.Channel.Bus.subscribe_session(session_id)
          rescue
            e ->
              Logger.warning(
                "AIBrain.Web.Socket failed to subscribe to session #{session_id}: #{Exception.message(e)}"
              )
          end

          %{state | subscribed_sessions: MapSet.put(state.subscribed_sessions, session_id)}
        else
          state
        end

      on_event = fn event ->
        send(ws_pid, {:ws_send, format_event(event, session_id)})
      end

      opts = Keyword.put(opts, :on_event, on_event)
      opts = Keyword.put(opts, :_history_loaded, true)

      case AIBrain.Session.Registry.try_register(session_id, self()) do
        :ok ->
          # Spawn all I/O and orchestrator work in a separate process so the WS
          # process stays free to forward streaming events without mailbox congestion.
          spawned_pid =
            spawn(fn ->
              receive do
                :go -> :ok
              end

              try do
                Logger.metadata(trace_id: trace_id, session_id: session_id)
                store = store()

                existing_messages =
                  case store.load_session(store, session_id) do
                    {:ok, session} -> session.messages
                    _ -> []
                  end

                Enum.each(messages, fn msg -> store.append_message(store, session_id, msg) end)

                run_query_inline(
                  ws_pid,
                  store,
                  session_id,
                  existing_messages ++ messages,
                  messages,
                  opts,
                  payload
                )
              rescue
                e ->
                  Logger.error(
                    "WebSocket spawn crashed for session #{session_id}: #{Exception.message(e)}"
                  )

                  if Process.alive?(ws_pid) do
                    send(
                      ws_pid,
                      {:ws_send,
                       Jason.encode!(%{
                         type: "error",
                         session_id: session_id,
                         error: "Internal error: #{Exception.message(e)}"
                       })}
                    )
                  end
              after
                AIBrain.Session.Registry.unregister(session_id)
              end
            end)

          AIBrain.Session.Registry.register(session_id, spawned_pid)
          send(spawned_pid, :go)

          {:ok, state}

        {:error, :already_running} ->
          error =
            Jason.encode!(%{
              type: "error",
              session_id: session_id,
              error: "Session is currently running"
            })

          {:push, [{:text, error}], state}
      end
    end
  end

  defp run_query_inline(ws_pid, store, session_id, all_messages, new_messages, opts, payload) do
    # Derive title update if needed
    prev_title =
      case store.load_session(store, session_id) do
        {:ok, %{title: t}} when is_binary(t) and t != "New Session" -> t
        _ -> "New Session"
      end

    new_title = AIBrain.Session.Store.derive_title_for_update(prev_title, new_messages)

    if new_title != "New Session" && new_title != prev_title do
      send(
        ws_pid,
        {:ws_send,
         Jason.encode!(%{
           type: "event",
           event: "session_title_updated",
           session_id: session_id,
           data: %{session_id: session_id, title: new_title}
         })}
      )
    end

    attrs = run_attrs(payload)

    result =
      try do
        AIBrain.AgentRuntime.Orchestrator.run_messages_auto(
          all_messages,
          opts,
          attrs
        )
      rescue
        e ->
          Logger.error(
            "WebSocket query crashed for session #{session_id}: #{Exception.message(e)}"
          )

          {:error, {:exception, Exception.message(e), e.__struct__}}
      catch
        :exit, {:session_aborted, _} ->
          {:error, :aborted}

        :exit, reason ->
          {:error, {:exit, reason}}

        :throw, value ->
          {:error, {:exception, inspect(value), RuntimeError}}
      end

    if Process.alive?(ws_pid) do
      case result do
        {:ok, _} -> AIBrain.Memory.Distiller.enqueue(session_id)
        _ -> :ok
      end

      payload =
        case result do
          {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
            %{
              type: "response",
              success: true,
              session_id: session_id,
              run_id: run_id,
              text: text
            }

          {:ok, %{run_id: run_id, result: {:suspended, meta}}} ->
            data = Map.put(meta, :session_id, session_id)

            %{
              type: "suspended",
              success: false,
              session_id: session_id,
              run_id: Map.get(meta, :run_id) || run_id,
              suspended: true,
              status: Map.get(meta, :status, "waiting_approval"),
              reason: Map.get(meta, :reason, "approval_required"),
              approval_id: Map.get(meta, :approval_id) || Map.get(meta, :interaction_id),
              interaction_id: Map.get(meta, :interaction_id),
              tool_name: Map.get(meta, :tool_name),
              data: data
            }

          {:ok, %{run_id: run_id, result: {:error, reason}}} ->
            Logger.error("WebSocket query failed for session #{session_id}: #{inspect(reason)}")

            %{
              type: "error",
              session_id: session_id,
              run_id: run_id,
              error: AIBrain.Core.ErrorFormatter.format_en(reason)
            }

          {:ok, %{run_id: run_id, result: {:error, reason, _detail}}} ->
            Logger.error("WebSocket query failed for session #{session_id}: #{inspect(reason)}")

            %{
              type: "error",
              session_id: session_id,
              run_id: run_id,
              error: AIBrain.Core.ErrorFormatter.format_en(reason)
            }

          {:error, reason} ->
            Logger.error("WebSocket query failed for session #{session_id}: #{inspect(reason)}")

            %{
              type: "error",
              session_id: session_id,
              error: AIBrain.Core.ErrorFormatter.format_en(reason)
            }
        end

      send(ws_pid, {:ws_send, Jason.encode!(payload)})
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:ok, state}
  end

  def handle_info({:session_event, session_id, event}, state) do
    data = format_event(event, session_id)
    {:push, [{:text, data}], state}
  end

  # Global Bus events — forward notification-relevant ones to frontend
  def handle_info({:bus_message, event}, state) when is_map(event) do
    type = event[:type] || event["type"]

    if type in ~w(scheduler_fired run_completed run_failed task_completed task_failed interaction_needed interaction_resolved interaction_escalated)a do
      data =
        Jason.encode!(%{
          type: "notification",
          event: to_string(type),
          data: event |> Map.drop([:type, :__struct__])
        })

      {:push, [{:text, data}], state}
    else
      {:ok, state}
    end
  end

  # Catch-all for bus messages
  def handle_info({:bus_message, _}, state), do: {:ok, state}

  def handle_info({:run_event, run_id, event}, state) do
    case format_run_event(run_id, event) do
      nil -> {:ok, state}
      data -> {:push, [{:text, data}], state}
    end
  end

  @impl WebSock
  def handle_info({:ws_send, data}, state) do
    {:push, [{:text, data}], state}
  end

  def handle_info({:send_event, event}, state) do
    data = Jason.encode!(event)
    {:push, [{:text, data}], state}
  end

  def handle_info({:monitor_notification, event}, state) do
    data =
      Jason.encode!(%{
        type: "monitor_notification",
        event: "monitor_result",
        data: %{
          monitor_id: event.monitor_id,
          name: event.name,
          result: event.result,
          started_at: event.started_at |> DateTime.to_iso8601(),
          completed_at: event.completed_at |> DateTime.to_iso8601()
        }
      })

    {:push, [{:text, data}], state}
  end

  @impl WebSock
  def handle_control(_frame, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, %{subscribed_sessions: sessions, subscribed_runs: runs} = _state) do
    try do
      AIBrain.Monitor.unsubscribe()
    rescue
      e ->
        Logger.error(
          "AIBrain.Web.Socket.terminate failed to unsubscribe from monitor: #{Exception.message(e)}"
        )

        :ok
    end

    # Unsubscribe from all session event channels
    Enum.each(sessions, fn sid ->
      try do
        AIBrain.Channel.Bus.unsubscribe_session(sid)
      rescue
        e ->
          Logger.warning(
            "Socket.terminate: failed to unsubscribe session #{sid}: #{Exception.message(e)}"
          )

          :ok
      end
    end)

    # Unsubscribe from all run event channels
    Enum.each(runs, fn rid ->
      try do
        AIBrain.Channel.Bus.unsubscribe_run(rid)
      rescue
        e ->
          Logger.warning(
            "Socket.terminate: failed to unsubscribe run #{rid}: #{Exception.message(e)}"
          )

          :ok
      end
    end)

    :ok
  end

  def terminate(_reason, _state) do
    try do
      AIBrain.Monitor.unsubscribe()
    rescue
      e ->
        Logger.warning(
          "Socket.terminate: failed to unsubscribe from monitor: #{Exception.message(e)}"
        )

        :ok
    end

    :ok
  end

  # 私有函数

  defp format_event(event, session_id) do
    try do
      encoded =
        case event do
          %{type: :tool_result, tool_use_id: id, result: result} ->
            {content, status} = normalize_tool_result(result)

            Jason.encode!(%{
              type: "event",
              event: "tool_result",
              session_id: session_id,
              data: %{
                session_id: session_id,
                tool_use_id: id,
                output: content,
                status: status
              }
            })

          %{type: :tool_timeout, tool_use_id: id, tool_name: name} ->
            Jason.encode!(%{
              type: "event",
              event: "tool_timeout",
              session_id: session_id,
              data: %{
                session_id: session_id,
                tool_use_id: id,
                tool_name: name,
                message: "Tool #{name} timed out after 60s",
                status: "error"
              }
            })

          %{type: :tool_crashed, tool_use_id: id, tool_name: name, reason: reason} ->
            message = "Tool #{name} crashed"

            Jason.encode!(%{
              type: "event",
              event: "tool_crashed",
              session_id: session_id,
              data: %{
                session_id: session_id,
                tool_use_id: id,
                tool_name: name,
                reason: AIBrain.Core.ErrorFormatter.format_en(reason),
                message: message,
                status: "error"
              }
            })

          %{type: :tool_exited, tool_use_id: id, tool_name: name, reason: reason} ->
            message = "Tool #{name} exited"

            Jason.encode!(%{
              type: "event",
              event: "tool_exited",
              session_id: session_id,
              data: %{
                session_id: session_id,
                tool_use_id: id,
                tool_name: name,
                reason: AIBrain.Core.ErrorFormatter.format_en(reason),
                message: message,
                status: "error"
              }
            })

          %{type: :provider_failed, reason: reason} = event ->
            provider_name = Map.get(event, :provider_name)

            Jason.encode!(%{
              type: "event",
              event: "provider_failed",
              session_id: session_id,
              data: %{
                session_id: session_id,
                provider_name: provider_name,
                reason: AIBrain.Core.ErrorFormatter.format_en(reason),
                retry_at: Map.get(event, :retry_at)
              }
            })

          _ ->
            type_str =
              if is_map(event) && Map.has_key?(event, :type),
                do: to_string(event.type),
                else: "unknown"

            serialized =
              event
              |> Map.drop([:__struct__, :__meta__])
              |> Enum.reduce(%{}, fn {k, v}, acc ->
                case safe_json_value(v) do
                  {:ok, val} -> Map.put(acc, k, val)
                  _ -> acc
                end
              end)

            Jason.encode!(%{
              type: "event",
              event: type_str,
              session_id: session_id,
              data: maybe_put_session_id(serialized, session_id)
            })
        end

      encoded
    rescue
      _ ->
        Jason.encode!(%{
          type: "event",
          event: "unknown",
          session_id: session_id,
          data: maybe_put_session_id(%{}, session_id)
        })
    end
  end

  defp maybe_put_session_id(data, nil), do: data
  defp maybe_put_session_id(data, session_id), do: Map.put_new(data, :session_id, session_id)

  defp extract_messages(%{"messages" => messages}) when is_list(messages) do
    {:ok, Enum.map(messages, &normalize_message/1)}
  end

  defp extract_messages(%{"message" => message}) when is_binary(message) do
    {:ok, [AIBrain.Message.from_json(%{"role" => "user", "content" => message})]}
  end

  defp extract_messages(_), do: {:error, "Invalid messages format"}

  defp normalize_tool_result(result) do
    case result do
      {:ok, output} when is_binary(output) -> {output, "success"}
      {:ok, output} when is_map(output) -> {inspect(output), "success"}
      {:error, reason} -> {format_tool_error(reason), "error"}
      %AIBrain.Tool.Result{content: content, success: true} -> {content, "success"}
      %AIBrain.Tool.Result{content: content, success: false} -> {content, "error"}
      %AIBrain.Tool.Error{message: msg} -> {msg, "error"}
      _ when is_binary(result) -> {result, "success"}
      _ -> {inspect(result), "success"}
    end
  end

  defp format_tool_error(%AIBrain.Tool.Error{message: msg}), do: msg
  defp format_tool_error(reason) when is_binary(reason), do: reason
  defp format_tool_error(reason), do: inspect(reason)

  defp safe_json_value(v), do: {:ok, stringify_values(v)}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_values(v)}
      {k, v} -> {k, stringify_values(v)}
    end)
  end

  defp stringify_values(%{__struct__: _} = s), do: s |> Map.from_struct() |> stringify_keys()
  defp stringify_values(v) when is_map(v), do: stringify_keys(v)
  defp stringify_values({:ok, value}), do: stringify_values(value)
  defp stringify_values({:error, reason}), do: stringify_values(reason)
  defp stringify_values(v) when is_tuple(v), do: Tuple.to_list(v) |> Enum.map(&stringify_values/1)
  defp stringify_values(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify_values(v), do: v

  defp require_session_id(opts) do
    case Keyword.get(opts, :session_id) do
      nil -> {:error, "session_id required"}
      id when is_binary(id) -> {:ok, id}
    end
  end

  defp normalize_message(msg) when is_map(msg), do: AIBrain.Message.from_json(msg)

  defp normalize_message(msg) when is_binary(msg),
    do: AIBrain.Message.from_json(%{"role" => "user", "content" => msg})

  defp load_session_workspace(session_id) do
    case store().load_session(store(), session_id) do
      {:ok, %{workspace_path: path}} when is_binary(path) -> path
      _ -> nil
    end
  end

  defp build_opts(params, _state) do
    session_id = Map.get(params, "session_id")
    explicit_workspace = Map.get(params, "workspace_path")
    mode = Map.get(params, "mode")

    base_opts = [session_store: store()]

    base_opts =
      case Map.get(params, "model") do
        model when is_binary(model) and model != "" -> Keyword.put(base_opts, :model, model)
        _ -> base_opts
      end

    base_opts =
      if mode do
        mode_atom =
          case mode do
            "default" ->
              :default

            "simple" ->
              :simple

            "creative" ->
              :creative

            "precise" ->
              :precise

            "execute" ->
              :execute

            _ ->
              Logger.warning("Unknown WebSocket mode '#{mode}', defaulting to :default")
              :default
          end

        Keyword.put(base_opts, :mode, mode_atom)
      else
        base_opts
      end

    opts =
      if session_id do
        existing = load_session_workspace(session_id)
        opts = Keyword.put(base_opts, :session_id, session_id)
        workspace = explicit_workspace || existing

        if workspace, do: Keyword.put(opts, :workspace_path, workspace), else: opts
      else
        workspace = explicit_workspace

        if workspace, do: Keyword.put(base_opts, :workspace_path, workspace), else: base_opts
      end

    opts =
      opts
      |> Keyword.put(:permission_mode, :approval_required)
      |> Keyword.put(:run_policy, :always)
      |> maybe_put_autonomy_level(params)

    {:ok, opts}
  end

  defp maybe_put_autonomy_level(opts, params) do
    case Map.get(params, "autonomy_level") do
      level when is_integer(level) -> Keyword.put(opts, :autonomy_level, level)
      level when is_binary(level) ->
        case Integer.parse(level) do
          {int, _} -> Keyword.put(opts, :autonomy_level, int)
          :error -> opts
        end
      _ -> opts
    end
  end

  defp run_attrs(params) do
    metadata =
      params
      |> Map.get("metadata", %{})
      |> case do
        value when is_map(value) -> value
        _ -> %{}
      end

    %{}
    |> maybe_put_attr(:mode, Map.get(params, "run_mode"))
    |> maybe_put_attr(:goal_id, Map.get(params, "goal_id"))
    |> maybe_put_attr(:autonomy_level, Map.get(params, "autonomy_level"))
    |> maybe_put_attr(:metadata, metadata)
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, _key, ""), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  defp handle_subscribe_run(%{"run_id" => run_id}, state) when is_binary(run_id) do
    try do
      AIBrain.Channel.Bus.subscribe_run(run_id)
      new_state = %{state | subscribed_runs: MapSet.put(state.subscribed_runs, run_id)}
      {:push, [{:text, Jason.encode!(%{type: "subscribed_run", run_id: run_id})}], new_state}
    rescue
      e ->
        Logger.warning(
          "AIBrain.Web.Socket failed to subscribe to run #{run_id}: #{Exception.message(e)}"
        )

        error = Jason.encode!(%{type: "error", error: "Failed to subscribe to run"})
        {:push, [{:text, error}], state}
    end
  end

  defp handle_subscribe_run(_payload, state) do
    error = Jason.encode!(%{type: "error", error: "Invalid run_id"})
    {:push, [{:text, error}], state}
  end

  defp handle_unsubscribe_run(%{"run_id" => run_id}, state) when is_binary(run_id) do
    try do
      AIBrain.Channel.Bus.unsubscribe_run(run_id)
      new_state = %{state | subscribed_runs: MapSet.delete(state.subscribed_runs, run_id)}
      {:push, [{:text, Jason.encode!(%{type: "unsubscribed_run", run_id: run_id})}], new_state}
    rescue
      e ->
        Logger.warning(
          "AIBrain.Web.Socket failed to unsubscribe from run #{run_id}: #{Exception.message(e)}"
        )

        error = Jason.encode!(%{type: "error", error: "Failed to unsubscribe from run"})
        {:push, [{:text, error}], state}
    end
  end

  defp handle_unsubscribe_run(_payload, state) do
    error = Jason.encode!(%{type: "error", error: "Invalid run_id"})
    {:push, [{:text, error}], state}
  end

  defp format_run_event(run_id, event) do
    try do
      case event do
        %{type: :run_event, run_id: event_run_id, event: inner_event}
        when is_binary(event_run_id) ->
          inner_data = format_inner_run_event(inner_event)

          Jason.encode!(%{
            type: "event",
            event: "run_event",
            data: Map.put(inner_data, :run_id, event_run_id)
          })

        %{type: type} = inner_event
        when is_binary(run_id) and
               type in [:tool_start, :tool_result, :tool_error, :turn_complete, :error] ->
          inner_data = format_inner_run_event(inner_event)

          Jason.encode!(%{
            type: "event",
            event: "run_event",
            data: Map.put(inner_data, :run_id, run_id)
          })

        _ ->
          nil
      end
    rescue
      _ ->
        nil
    end
  end

  defp format_inner_run_event(%{type: :tool_start, tool_name: name, tool_use_id: id}) do
    %{
      tool_name: name,
      tool_use_id: id,
      status: "started"
    }
  end

  defp format_inner_run_event(%{type: :tool_result, tool_use_id: id, result: result}) do
    {content, status} = normalize_tool_result(result)

    %{
      tool_use_id: id,
      output: content,
      status: status
    }
  end

  defp format_inner_run_event(%{type: :tool_error, tool_name: name, error: error}) do
    %{
      tool_name: name,
      error: AIBrain.Core.ErrorFormatter.format_en(error),
      status: "error"
    }
  end

  defp format_inner_run_event(%{type: :turn_complete, turn_number: n, content: content}) do
    %{
      turn_number: n,
      content: content,
      status: "complete"
    }
  end

  defp format_inner_run_event(%{type: :error, reason: reason}) do
    %{
      error: AIBrain.Core.ErrorFormatter.format_en(reason),
      status: "error"
    }
  end

  defp format_inner_run_event(event) do
    # Fallback for unknown event types
    event
    |> Map.drop([:__struct__, :__meta__])
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      case safe_json_value(v) do
        {:ok, val} -> Map.put(acc, k, val)
        _ -> acc
      end
    end)
  end
end
