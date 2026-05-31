defmodule AIBrain.Channel.AdapterWorker do
  @moduledoc """
  GenServer that runs a channel adapter, routing inbound messages through
  SessionChannel and outbound replies back through the adapter.
  """
  require Logger

  use GenServer

  alias AIBrain.Channel.{Consumer, SessionChannel}

  defstruct [:adapter, :adapter_state, :consumer, :channel, :session_channel]

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    registry = Keyword.get(opts, :registry)

    start_opts =
      if registry do
        {registry_mod, key} = registry
        [name: {:via, Registry, {registry_mod, key}}]
      else
        if name, do: [name: name], else: []
      end

    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def deliver_inbound(server, payload) do
    GenServer.call(server, {:inbound, payload}, :infinity)
  end

  def notify(server, event) do
    # server can be a pid, a registered name atom, or {registry, key} tuple
    pid =
      case server do
        {registry, key} when is_atom(registry) ->
          case Registry.lookup(registry, key) do
            [{pid, _}] -> pid
            [] -> nil
          end

        pid when is_pid(pid) ->
          pid

        name when is_atom(name) ->
          Process.whereis(name)
      end

    if pid do
      GenServer.cast(pid, {:notify, event})
    else
      Logger.warning("AdapterWorker.notify: Failed to find process for #{inspect(server)}")
    end
  end

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])
    channel = Keyword.get(opts, :channel, :unknown)

    case adapter.init(adapter_opts) do
      {:ok, adapter_state} ->
        {:ok, consumer} = Consumer.start_link(channel: channel)
        {:ok, session_channel} = SessionChannel.start_link([])

        state = %__MODULE__{
          adapter: adapter,
          adapter_state: adapter_state,
          consumer: consumer,
          channel: channel,
          session_channel: session_channel
        }

        # Start Telegram poller after a brief delay to let init complete
        Process.send_after(self(), {:start_poller, adapter, adapter_state}, 500)

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Interaction callback data format:
  #   ia:a:{id}       — approve (confirm)
  #   ia:d:{id}       — deny (confirm)
  #   ia:s:{id}:{idx} — select option (select)
  def parse_interaction_callback("ia:a:" <> id), do: {:interaction, id, :approve, nil}
  def parse_interaction_callback("ia:d:" <> id), do: {:interaction, id, :deny, nil}

  def parse_interaction_callback("ia:s:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [id, index_str] ->
        case Integer.parse(index_str) do
          {idx, _} -> {:interaction, id, :select, idx}
          :error -> :skip
        end

      _ ->
        :skip
    end
  end

  def parse_interaction_callback(_), do: :skip

  @impl true
  def handle_call({:inbound, payload}, _from, state) do
    case route_inbound(payload, state) do
      {:query, messages, new_adapter_state} ->
        state = %{state | adapter_state: new_adapter_state}

        results =
          Enum.flat_map(messages, fn msg ->
            case run_query(state, msg) do
              {:ok, replies} ->
                replies

              {:error, reason} ->
                Logger.error("AdapterWorker[#{state.channel}]: Query failed: #{inspect(reason)}")

                error_msg = %{
                  content:
                    "⚠️ 请求处理失败: #{AIBrain.Core.ErrorFormatter.format_zh(reason)}\n请稍后重试或检查服务状态。"
                }

                case state.adapter.send_message(state.adapter_state, error_msg) do
                  {:ok, _new_state} ->
                    :ok

                  {:error, send_err} ->
                    Logger.error(
                      "AdapterWorker[#{state.channel}]: Failed to send error message: #{inspect(send_err)}"
                    )
                end

                [error_msg]
            end
          end)

        {:reply, {:ok, results}, state}
    end
  end

  defp route_inbound(%{"callback_query" => %{"data" => data}}, state) do
    if String.starts_with?(data, "ia:") do
      case parse_interaction_callback(data) do
        {:interaction, id, action, extra} ->
          resolve_interaction(id, action, extra, state.channel)
          {:query, [], state}

        _ ->
          {:query, [], state}
      end
    else
      {:query, [], state}
    end
  end

  defp route_inbound(payload, state) do
    case state.adapter.handle_inbound(state.adapter_state, payload) do
      {:ok, messages, new_adapter_state} -> {:query, messages, new_adapter_state}
      {:error, _} -> {:query, [], state.adapter_state}
    end
  end

  @impl true
  def handle_cast({:notify, event}, state) do
    Logger.info("AdapterWorker[#{state.channel}]: Received notification #{inspect(event.type)}")

    reply = build_notify_reply(event)

    case state.adapter.send_message(state.adapter_state, reply) do
      {:ok, new_state} ->
        Logger.info("AdapterWorker[#{state.channel}]: Message sent successfully")
        {:noreply, %{state | adapter_state: new_state}}

      {:error, reason} ->
        Logger.error(
          "AdapterWorker[#{state.channel}]: Failed to send message: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  defp build_notify_reply(%{type: :interaction_escalated} = event) do
    interaction_id = event.interaction_id

    case AIBrain.Data.Interactions.get(interaction_id) do
      nil ->
        %{
          content:
            "⚠️ Interaction #{interaction_id} requires your attention, but details are no longer available."
        }

      interaction ->
        %{
          type: :interaction,
          interaction_id: interaction_id,
          interaction_type: interaction.type,
          schema: interaction.schema_data,
          context: interaction.context,
          reason: Map.get(event, :reason, "")
        }
    end
  end

  defp build_notify_reply(%{type: :interaction_resolved} = event) do
    by = event.resolved_by

    action =
      case event.result do
        %{decision: :approved} -> "✅ Approved"
        %{decision: :denied, reason: r} -> "❌ Denied#{if r, do: ": #{r}"}"
        %{text: t} -> "✍️ Answered: #{String.slice(t || "", 0, 100)}"
        %{selected_index: i} -> "🔘 Selected option ##{i}"
        %{form: _} -> "📋 Form submitted"
        _ -> "Resolved"
      end

    %{
      content:
        "Interaction #{String.slice(event.interaction_id || "", 0, 8)} #{action} (by #{by})"
    }
  end

  defp build_notify_reply(%{type: :approval_needed} = event) do
    %{
      type: :approval,
      approval_id: event.approval_id,
      tool_name: event.tool_name,
      input: event.input,
      form_type: Map.get(event, :form_type, :confirm),
      options: Map.get(event, :options, [])
    }
  end

  defp build_notify_reply(event) do
    %{
      role: "assistant",
      content: format_event(event),
      metadata: %{surface: :notification, event_type: event.type}
    }
  end

  defp run_query(state, %{role: "user", content: _content} = msg) do
    opts = build_opts(state)
    messages = [msg]

    case SessionChannel.run(state.session_channel, messages, opts) do
      {:ok, text, _history} ->
        published = Consumer.published(state.consumer)
        deliver_published(state, published)
        main_reply = %{role: "assistant", content: text}
        state.adapter.send_message(state.adapter_state, main_reply)
        {:ok, [main_reply | published]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_query(_state, _msg), do: {:error, :invalid_message}

  defp deliver_published(state, published) do
    Enum.each(published, fn reply ->
      state.adapter.send_message(state.adapter_state, reply)
    end)
  end

  defp build_opts(state) do
    store = AIBrain.Config.session_store()
    channel_adapter = to_string(state.channel)
    channel_id = channel_id_from(state)

    # Resolve or create session deduplicated by channel_adapter+channel_id
    {session_id, _status} =
      AIBrain.Session.Store.find_or_create_session!(store,
        channel_adapter: channel_adapter,
        channel_id: channel_id,
        session_type: "telegram_chat"
      )

    [
      session_store: store,
      session_id: session_id,
      session_type: "telegram_chat",
      channel_adapter: channel_adapter,
      channel_id: channel_id,
      on_event: fn event ->
        # Skip internal tracking events that are noise in Telegram
        if event.type not in [:query_started, :query_complete] do
          GenServer.cast(self(), {:notify, event})
        end
      end
    ]
  end

  defp resolve_interaction(id, :approve, _extra, channel) do
    AIBrain.Interaction.Manager.resolve(id, %{decision: :approved}, to_string(channel))
  rescue
    _ -> :ok
  end

  defp resolve_interaction(id, :deny, _extra, channel) do
    AIBrain.Interaction.Manager.resolve(id, %{decision: :denied}, to_string(channel))
  rescue
    _ -> :ok
  end

  defp resolve_interaction(id, :select, index, channel) when is_integer(index) do
    AIBrain.Interaction.Manager.resolve(id, %{selected_index: index}, to_string(channel))
  rescue
    _ -> :ok
  end

  defp channel_id_from(state) do
    case state.adapter_state do
      %{chat_id: id} when is_binary(id) -> id
      %{chat_id: id} when is_integer(id) -> Integer.to_string(id)
      _ -> "unknown"
    end
  end

  defp format_event(%{type: :tool_result, tool_use_id: _id, result: result, tool_name: name}) do
    case result do
      {:ok, output} when is_binary(output) ->
        "✅ #{name} completed:\n#{String.slice(output, 0, 500)}"

      {:ok, output} when is_map(output) ->
        "✅ #{name} completed: #{inspect(output)}"

      {:error, reason} ->
        "❌ #{name} failed: #{inspect(reason)}"

      _ when is_binary(result) ->
        "✅ #{name} completed:\n#{String.slice(result, 0, 500)}"

      _ ->
        "✅ #{name} completed"
    end
  end

  defp format_event(%{type: :task_failed, task_id: id, reason: reason}) do
    "❌ 任务失败 [#{id}]: #{inspect(reason)}"
  end

  defp format_event(%{type: :task_completed, task_id: id}), do: "✅ Task #{id} completed."
  defp format_event(%{type: :task_failed, task_id: id}), do: "❌ Task #{id} failed."
  defp format_event(%{type: :scheduler_wake, cause: cause}), do: "⏰ Scheduler wake: #{cause}"

  defp format_event(%{type: :run_completed, run_id: id, status: status}) do
    emoji = if status == :completed, do: "✅", else: "⚠️"
    "#{emoji} Run #{String.slice(id, 0, 8)} #{status}."
  end

  defp format_event(%{
         type: :run_event,
         run_id: _id,
         agent_name: name,
         event: %{type: event_type}
       }) do
    case event_type do
      :tool_start -> "🔧 [#{name}] Starting tool execution..."
      :tool_result -> "✅ [#{name}] Tool completed"
      :tool_error -> "❌ [#{name}] Tool failed"
      :turn_complete -> "💬 [#{name}] Turn completed"
      _ -> "ℹ️ [#{name}] #{event_type}"
    end
  end

  defp format_event(%{type: :delegation_event, assistant_name: name, status: status, task: task}) do
    case status do
      :start -> "👥 Delegating to '#{name}': #{String.slice(task, 0, 100)}"
      _ -> "ℹ️ Delegation #{status}: #{name}"
    end
  end

  defp format_event(%{type: :query_complete, session_id: sid}) do
    "💬 Query #{String.slice(sid, 0, 8)} completed."
  end

  defp format_event(%{type: :error, message: msg}) do
    "🚨 Error: #{msg}"
  end

  defp format_event(%AIBrain.Channel.Alert{severity: sev, source: src, type: type, message: msg}) do
    emoji =
      case sev do
        :critical -> "🔴"
        :warning -> "🟡"
        :info -> "ℹ️"
      end

    "#{emoji} [#{sev |> to_string() |> String.upcase()}] #{src}:#{type} — #{msg}"
  end

  defp format_event(event), do: "ℹ️ Event: #{event.type}"

  @impl true
  def handle_info({:start_poller, AIBrain.Channel.Adapters.TelegramAdapter, adapter_state}, state) do
    bot_token = Map.get(adapter_state, :bot_token)

    if bot_token && bot_token != "" do
      {:ok, _pid} =
        AIBrain.Channel.Adapters.TelegramPoller.start_link(
          bot_token: bot_token,
          worker: self(),
          store: Application.get_env(:ai_brain, :session_store, AIBrain.Session.Store.SQLite)
        )

      Logger.info(
        "AdapterWorker: Started Telegram poller for #{String.slice(bot_token, 0, 12)}..."
      )
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
