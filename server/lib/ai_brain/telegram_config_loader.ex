defmodule AIBrain.TelegramConfigLoader do
  @moduledoc """
  Loads channel configs from DB and registers gateway adapters.
  Despite the name, now handles all 5 platforms.
  """

  require Logger
  alias AIBrain.Data.ChannelConfigs

  def load_and_register do
    {:ok, configs} = ChannelConfigs.list_all()

    enabled = Enum.filter(configs, & &1.enabled)

    Logger.info(
      "ChannelLoader: Loading #{length(enabled)} enabled channel(s) out of #{length(configs)} total"
    )

    adapter_opts =
      Enum.map(enabled, fn config ->
        creds = decode_json(config.credentials)
        extra = decode_json(config.extra)
        all = Map.merge(creds, extra)

        case config.channel_type do
          "telegram" ->
            {AIBrain.Channel.Adapters.TelegramAdapter,
             [bot_token: all["bot_token"], chat_id: all["chat_id"]]}

          "discord" ->
            {AIBrain.Channel.Adapters.DiscordAdapter,
             [bot_token: all["bot_token"], application_id: all["application_id"]]}

          "feishu" ->
            {AIBrain.Channel.Adapters.FeishuAdapter,
             [app_id: all["app_id"], app_secret: all["app_secret"], chat_id: all["chat_id"]]}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Application.put_env(:ai_brain, :gateway_adapters, adapter_opts)

    restart_gateway(adapter_opts)

    # Workers register themselves asynchronously — brief wait
    Process.sleep(200)
    start_pollers(enabled)
  end

  defp restart_gateway(adapter_opts) do
    case Supervisor.terminate_child(AIBrain.Supervisor, AIBrain.Channel.Gateway) do
      :ok ->
        Supervisor.delete_child(AIBrain.Supervisor, AIBrain.Channel.Gateway)

        gateway_spec = {
          AIBrain.Channel.Gateway,
          [adapters: adapter_opts, name: AIBrain.Channel.Gateway]
        }

        case Supervisor.start_child(AIBrain.Supervisor, gateway_spec) do
          {:ok, _pid} ->
            Logger.info(
              "ChannelLoader: Gateway restarted with #{length(adapter_opts)} adapter(s)"
            )

            :ok

          {:error, reason} ->
            Logger.error("ChannelLoader: Gateway start failed: #{inspect(reason)}")
            :error
        end

      {:error, reason} ->
        Logger.error("ChannelLoader: Gateway terminate failed: #{inspect(reason)}")
        :error
    end
  end

  defp start_pollers(enabled_configs) do
    telegram_configs = Enum.filter(enabled_configs, &(&1.channel_type == "telegram"))

    Enum.with_index(telegram_configs, fn config, idx ->
      creds = decode_json(config.credentials)
      bot_token = creds["bot_token"]

      if bot_token && bot_token != "" do
        worker_key = {AIBrain.Channel.Adapters.TelegramAdapter, idx}

        case Registry.lookup(AIBrain.Channel.Gateway.Registry, worker_key) do
          [{worker_pid, _}] ->
            {:ok, _pid} =
              AIBrain.Channel.Adapters.TelegramPoller.start_link(
                bot_token: bot_token,
                worker: worker_pid,
                store: AIBrain.Session.Store.SQLite
              )

            Logger.info(
              "TelegramConfigLoader: Started poller for #{String.slice(bot_token, 0, 12)}..."
            )

          [] ->
            Logger.warning("TelegramConfigLoader: No worker found for Telegram config idx #{idx}")
        end
      end
    end)
  end

  defp decode_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, m} -> m
      _ -> %{}
    end
  end

  defp decode_json(_), do: %{}
end
