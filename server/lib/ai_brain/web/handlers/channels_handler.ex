defmodule AIBrain.Web.Handlers.ChannelsHandler do
  @moduledoc """
  Handler for channel-level operations, including merged message timelines
  across session rotations.
  """
  import Plug.Conn
  require Logger

  alias AIBrain.ConversationLog

  def handle_get_messages(conn, adapter, channel_id) do
    offset = parse_int(conn.params["offset"], 0)
    limit = parse_int(conn.params["limit"], 50) |> min(100)

    sessions = find_sessions_by_channel(adapter, channel_id)

    all_messages =
      Enum.flat_map(sessions, fn session ->
        case ConversationLog.load_conversation(session.session_id) do
          {:ok, messages, _log} ->
            Enum.map(messages, fn msg ->
              msg
              |> Map.from_struct()
              |> Map.put("_session_id", session.session_id)
              |> Map.put("_session_title", session.title)
            end)

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn msg ->
        msg["created_at"] || msg["id"] || ""
      end)

    total = length(all_messages)
    paged = Enum.drop(all_messages, offset) |> Enum.take(limit)

    json(conn, 200, %{
      messages: paged,
      total: total,
      offset: offset,
      limit: limit,
      session_count: length(sessions)
    })
  end

  defp find_sessions_by_channel(adapter, channel_id) do
    pattern = "%#{sanitize_like(adapter)}%"

    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id, title, started_at FROM sessions WHERE channel_adapter LIKE ? AND channel_id = ? ORDER BY started_at ASC",
        [pattern, channel_id]
      )

    Enum.map(result.rows, fn [id, title, started_at] ->
      %{session_id: id, title: title || id, created_at: started_at}
    end)
  rescue
    e ->
      Logger.error("ChannelsHandler.find_sessions_by_channel failed: #{Exception.message(e)}")
      []
  end

  defp sanitize_like(str) when is_binary(str) do
    str |> String.replace("%", "\\%") |> String.replace("_", "\\_")
  end

  defp sanitize_like(nil), do: ""

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n >= 0 -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
