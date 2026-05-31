defmodule AIBrain.Channel.DispatchQueue do
  @moduledoc """
  Reliable delivery queue for outbound notifications.

  - Polls the notification_queue table every 5 seconds for pending items
  - Supports channel-specific delivery (telegram, websocket, desktop)
  - Telegram: serial delivery via AdapterWorker, exponential backoff
    (10s, 30s, 90s, 270s, max 810s, 5 retries)
  - Websocket: instant push, no retry queue
  - Desktop: osascript notification, 1 retry then discard
  """

  use GenServer
  require Logger

  @poll_interval 5_000

  # ── Client API ───────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ── Callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    send(self(), :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    try do
      items = AIBrain.Data.NotificationQueue.get_pending()
      Enum.each(items, &process_item/1)
    rescue
      e -> Logger.error("DispatchQueue poll error: #{Exception.message(e)}")
    end

    Process.send_after(self(), :poll, @poll_interval)
    {:noreply, state}
  end

  # ── Delivery logic ───────────────────────────────────────────────────

  defp process_item(item) do
    AIBrain.Data.NotificationQueue.mark_delivering(item.id)

    case deliver(item) do
      :ok ->
        AIBrain.Data.NotificationQueue.mark_delivered(item.id)
        Logger.debug("DispatchQueue: delivered #{item.id} via #{item.channel}")

      {:error, reason} ->
        handle_failure(item, reason)
    end
  end

  defp deliver(%{channel: channel, payload: payload})
       when channel in ~w(telegram discord feishu wechat whatsapp) do
    # Reconstruct the event from the stored payload and forward to the
    # appropriate adapter worker(s) via their registry names.
    event = reconstruct_event(payload)
    workers = find_workers_for_channel(channel)

    if workers == [] do
      {:error, "no #{channel} adapter configured"}
    else
      Enum.each(workers, fn {mod, idx} ->
        name = AIBrain.Channel.Gateway.adapter_worker(mod, idx)
        AIBrain.Channel.AdapterWorker.notify(name, event)
      end)

      :ok
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp deliver(%{channel: "websocket"}) do
    # Websocket messages are delivered instantly via Bus / EventBuffer.
    # No queue-level retry is needed.
    :ok
  end

  defp deliver(%{channel: "desktop", payload: payload}) do
    case System.cmd("osascript", ["-e", build_desktop_script(payload)]) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp handle_failure(item, reason) do
    if item.retry_count >= item.max_retries do
      AIBrain.Data.NotificationQueue.mark_failed(item.id, reason)

      Logger.error(
        "DispatchQueue: #{item.id} (#{item.channel}) " <>
          "failed after #{item.retry_count} retries: #{reason}"
      )
    else
      AIBrain.Data.NotificationQueue.increment_retry(item.id, reason)

      Logger.warning(
        "DispatchQueue: #{item.id} (#{item.channel}) " <>
          "retry #{item.retry_count + 1}/#{item.max_retries}: #{reason}"
      )
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp reconstruct_event(payload) when is_map(payload) do
    # Try to convert string keys from the JSON payload back to atom keys
    # so that AdapterWorker's format_event/1 pattern matches work correctly.
    # Falls back to the string-keyed map if atom conversion fails.
    Map.new(payload, fn
      {key, val} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), val}
        rescue
          _ -> {key, val}
        end

      {key, val} ->
        {key, val}
    end)
  end

  defp reconstruct_event(payload), do: payload

  defp find_workers_for_channel(channel_str) do
    channel_atom = String.to_existing_atom(channel_str)

    Application.get_env(:ai_brain, :gateway_adapters, [])
    |> Enum.with_index()
    |> Enum.filter(fn {{mod, _opts}, _idx} ->
      function_exported?(mod, :channel, 0) && mod.channel() == channel_atom
    end)
    |> Enum.map(fn {{mod, _opts}, idx} -> {mod, idx} end)
  rescue
    _ -> []
  end

  defp build_desktop_script(payload) do
    title = payload["title"] || payload[:title] || "AIBrain"
    body = payload["body"] || payload[:body] || "Notification"

    ~s(display notification "#{escape_apple_script(body)}" with title "#{escape_apple_script(title)}")
  end

  defp escape_apple_script(s) do
    s |> to_string() |> String.replace(~s("), ~s(\\"))
  end
end
