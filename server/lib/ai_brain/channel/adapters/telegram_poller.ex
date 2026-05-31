defmodule AIBrain.Channel.Adapters.TelegramPoller do
  @moduledoc """
  Polls Telegram getUpdates when webhook is unavailable (local dev).

  Each poller instance is tied to one Telegram bot token and one adapter worker.
  """

  use GenServer
  require Logger

  @poll_interval_ms 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    bot_token = Keyword.fetch!(opts, :bot_token)
    worker = Keyword.fetch!(opts, :worker)
    store = Keyword.fetch!(opts, :store)

    state = %{
      bot_token: bot_token,
      worker: worker,
      store: store,
      offset: nil
    }

    schedule_poll()
    Logger.info("TelegramPoller: Started for bot #{String.slice(bot_token, 0, 12)}...")
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = fetch_updates(state)
    schedule_poll()
    {:noreply, new_state}
  end

  defp fetch_updates(state) do
    token = String.replace_prefix(state.bot_token, "bot", "")
    url = "https://api.telegram.org/bot#{token}/getUpdates"
    url = if state.offset, do: "#{url}?offset=#{state.offset}&timeout=1", else: "#{url}?timeout=1"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => updates}}} when is_list(updates) ->
        Enum.reduce(updates, state, fn update, acc ->
          handle_update(acc, update)
        end)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("TelegramPoller: getUpdates HTTP #{status}: #{inspect(body)}")
        state

      {:error, reason} ->
        Logger.warning("TelegramPoller: getUpdates failed: #{inspect(reason)}")
        state
    end
  end

  defp handle_update(state, %{"update_id" => id} = update) do
    new_state = Map.put(state, :offset, id + 1)

    try do
      AIBrain.Channel.AdapterWorker.deliver_inbound(state.worker, update)
    rescue
      e -> Logger.warning("TelegramPoller: deliver_inbound error: #{Exception.message(e)}")
    catch
      _, reason -> Logger.warning("TelegramPoller: deliver_inbound caught: #{inspect(reason)}")
    end

    new_state
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
end
