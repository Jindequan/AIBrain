defmodule AIBrain.Channel.Notifier do
  @moduledoc """
  Dispatches runtime events to configured gateway adapters.

  All channel types (telegram, discord, feishu, wechat, whatsapp) are
  enqueued to `AIBrain.Data.NotificationQueue` for reliable delivery with
  retry via `AIBrain.Channel.DispatchQueue`. This is channel-agnostic —
  no adapter type is special-cased.

  WebSocket and desktop channels are handled separately via Bus and are
  not part of the gateway adapter system.
  """

  require Logger

  def dispatch(event, adapters \\ nil) do
    adapters = adapters || configured_adapters()

    Logger.info(
      "Notifier: Dispatching event #{inspect(event_type(event))} to #{length(adapters)} adapter(s)"
    )

    Enum.each(adapters, fn {worker_name, _idx} ->
      channel = channel_for_adapter(worker_name)
      enqueue_notification(event, channel)
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp configured_adapters do
    Application.get_env(:ai_brain, :gateway_adapters, [])
    |> Enum.with_index()
    |> Enum.map(fn {{mod, _opts}, idx} -> {mod, idx} end)
  end

  defp channel_for_adapter(mod) do
    if function_exported?(mod, :channel, 0) do
      mod.channel() |> to_string()
    else
      "unknown"
    end
  end

  defp enqueue_notification(event, channel) do
    event_id = Map.get(event, :id, Map.get(event, :event_id, Ecto.UUID.generate()))
    payload = build_payload(event)

    AIBrain.Data.NotificationQueue.create(%{
      event_id: event_id,
      channel: channel,
      payload: payload,
      max_retries: 5
    })
  rescue
    e ->
      Logger.warning(
        "Notifier: failed to enqueue notification for #{channel}: #{Exception.message(e)}"
      )

      :ok
  end

  defp build_payload(event) do
    case event do
      %{__struct__: _} -> Map.from_struct(event) |> Map.drop([:__struct__])
      map when is_map(map) -> map
      _ -> %{value: event}
    end
  end

  defp event_type(event) do
    cond do
      is_map(event) && Map.has_key?(event, :type) -> event.type
      is_map(event) && Map.has_key?(event, "type") -> event["type"]
      true -> inspect(event)
    end
  end
end
