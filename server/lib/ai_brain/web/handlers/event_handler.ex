defmodule AIBrain.Web.Handlers.EventHandler do
  @moduledoc """
  Handler for session event replay endpoint.

  The frontend calls this after WebSocket reconnection to replay events
  it missed while disconnected.
  """

  import Plug.Conn
  require Logger

  def handle_get_events(conn, session_id) do
    since = parse_seq(conn.params["since"])

    events = AIBrain.Session.EventBuffer.get_events_since(session_id, since)
    latest_seq = AIBrain.Session.EventBuffer.latest_seq(session_id)

    json_response(conn, 200, %{
      session_id: session_id,
      events: events,
      latest_seq: latest_seq,
      since: since
    })
  end

  defp parse_seq(nil), do: 0
  defp parse_seq(""), do: 0

  defp parse_seq(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_seq(n) when is_integer(n), do: n
  defp parse_seq(_), do: 0

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
