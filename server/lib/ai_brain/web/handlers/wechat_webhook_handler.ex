defmodule AIBrain.Web.Handlers.WechatWebhookHandler do
  @moduledoc """
  Handles inbound WeChat bridge webhook requests.

  The bridge sends POST with JSON: { from, text, type, chat_type, webhook_secret }
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
        json_response(conn, 503, %{error: "WeChat gateway not configured"})

      worker ->
        case AIBrain.Channel.AdapterWorker.deliver_inbound(worker, update) do
          {:ok, results} ->
            reply = extract_reply(results)
            json_response(conn, 200, reply)

          {:error, reason} ->
            Logger.error("WeChat webhook processing failed: #{inspect(reason)}")
            json_response(conn, 500, %{error: "Failed to process webhook"})
        end
    end
  end

  defp get_adapter_worker do
    case Registry.lookup(
           AIBrain.Channel.Gateway.Registry,
           {AIBrain.Channel.Adapters.WechatAdapter, 0}
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
