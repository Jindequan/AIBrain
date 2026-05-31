defmodule AIBrain.Web.Handlers.WhatsappWebhookHandler do
  @moduledoc """
  Handles inbound WhatsApp bridge webhook requests.

  The bridge sends POST with JSON: { from, text, type, webhook_secret, has_media }
  AIBrain processes and returns the reply as JSON response.
  """

  import Plug.Conn
  require Logger

  def handle_webhook(conn, params) do
    dispatch_to_worker(conn, params)
  end

  defp dispatch_to_worker(conn, update) do
    case get_adapter_worker() do
      nil ->
        json_response(conn, 503, %{error: "WhatsApp gateway not configured"})

      worker ->
        case AIBrain.Channel.AdapterWorker.deliver_inbound(worker, update) do
          {:ok, results} ->
            reply = extract_reply(results)
            json_response(conn, 200, reply)

          {:error, reason} ->
            Logger.error("WhatsApp webhook processing failed: #{inspect(reason)}")
            json_response(conn, 500, %{error: "Failed to process webhook"})
        end
    end
  end

  defp get_adapter_worker do
    case Registry.lookup(
           AIBrain.Channel.Gateway.Registry,
           {AIBrain.Channel.Adapters.WhatsappAdapter, 0}
         ) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp extract_reply(results) do
    results
    |> Enum.find(& &1)
    |> case do
      nil -> %{text: "thinking...", status: "pending"}
      reply -> reply
    end
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
