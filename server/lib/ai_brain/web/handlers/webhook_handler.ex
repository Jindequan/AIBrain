defmodule AIBrain.Web.Handlers.WebhookHandler do
  @moduledoc """
  Handles inbound webhook requests from external channels.
  """

  import Plug.Conn
  require Logger

  def handle_telegram(conn, %{"message" => _} = update), do: dispatch_to_worker(conn, update)

  def handle_telegram(conn, %{"callback_query" => _} = update),
    do: dispatch_to_worker(conn, update)

  def handle_telegram(conn, _params) do
    json_response(conn, 400, %{error: "Invalid Telegram update"})
  end

  defp dispatch_to_worker(conn, update) do
    case get_adapter_worker() do
      nil ->
        json_response(conn, 503, %{error: "Gateway not configured"})

      worker ->
        case AIBrain.Channel.AdapterWorker.deliver_inbound(worker, update) do
          {:ok, _results} ->
            json_response(conn, 200, %{status: "ok"})

          {:error, reason} ->
            Logger.error("Telegram webhook processing failed: #{inspect(reason)}")
            json_response(conn, 500, %{error: "Failed to process webhook"})
        end
    end
  end

  defp get_adapter_worker do
    case Registry.lookup(
           AIBrain.Channel.Gateway.Registry,
           {AIBrain.Channel.Adapters.TelegramAdapter, 0}
         ) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
