defmodule AIBrain.Web.Handlers.DiscordWebhookHandler do
  @moduledoc """
  Handles inbound Discord interaction webhook requests.

  - PING (type 1) → responds with `{"type": 1}` to verify endpoint
  - All other payloads → dispatched to AdapterWorker for processing
  """

  import Plug.Conn
  require Logger

  def handle_webhook(conn, %{"type" => 1} = _params) do
    # Discord PING interaction: respond with PONG to verify endpoint
    json_response(conn, 200, %{type: 1})
  end

  def handle_webhook(conn, params) do
    dispatch_to_worker(conn, params)
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
            Logger.error("Discord webhook processing failed: #{inspect(reason)}")
            json_response(conn, 500, %{error: "Failed to process webhook"})
        end
    end
  end

  defp get_adapter_worker do
    case Registry.lookup(
           AIBrain.Channel.Gateway.Registry,
           {AIBrain.Channel.Adapters.DiscordAdapter, 0}
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
