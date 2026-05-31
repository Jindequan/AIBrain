defmodule AIBrain.Web.Handlers.SessionsHandler do
  import Plug.Conn
  alias AIBrain.Repo

  def handle_list(conn) do
    session_store = store()
    sessions = session_store.list_sessions(session_store)

    # Enrich sessions with a display-friendly workspace_name.
    # Home directory paths get "#" instead of the directory name.
    home = System.user_home!()

    sessions =
      Enum.map(sessions, fn s ->
        wp = s[:workspace_path] || s["workspace_path"]

        name =
          cond do
            is_nil(wp) -> nil
            wp == home -> "#"
            true -> String.split(wp, "/") |> List.last()
          end

        Map.put(s, :workspace_name, name)
      end)

    # Filter by workspace_path or scope
    workspace_path = conn.params["workspace_path"]
    scope = conn.params["scope"]

    sessions =
      cond do
        is_binary(workspace_path) and workspace_path != "" ->
          Enum.filter(sessions, fn s ->
            (s[:workspace_path] || s["workspace_path"]) == workspace_path
          end)

        scope == "chat" ->
          Enum.filter(sessions, fn s ->
            is_nil(s[:workspace_path] || s["workspace_path"])
          end)

        scope == "work" ->
          Enum.filter(sessions, fn s ->
            not is_nil(s[:workspace_path] || s["workspace_path"])
          end)

        true ->
          sessions
      end

    # Parse query params
    search = conn.params["search"]
    sort = conn.params["sort"] || "updated_at_desc"
    offset = parse_int(conn.params["offset"], 0)
    limit = parse_int(conn.params["limit"], 50) |> min(200)

    sessions =
      if is_binary(search) and search != "" do
        search_down = String.downcase(search)

        Enum.filter(sessions, fn s ->
          title = s[:title] || s["title"] || ""
          String.contains?(String.downcase(title), search_down)
        end)
      else
        sessions
      end

    # Filter by channel
    channel_adapter_filter = conn.params["channel_adapter"]

    sessions =
      if is_binary(channel_adapter_filter) and channel_adapter_filter != "" do
        Enum.filter(sessions, fn s ->
          (s[:channel_adapter] || s["channel_adapter"]) == channel_adapter_filter
        end)
      else
        sessions
      end

    channel_id_filter = conn.params["channel_id"]

    sessions =
      if is_binary(channel_id_filter) and channel_id_filter != "" do
        Enum.filter(sessions, fn s ->
          (s[:channel_id] || s["channel_id"]) == channel_id_filter
        end)
      else
        sessions
      end

    # Sort
    sessions = sort_sessions(sessions, sort)

    total = length(sessions)

    # Paginate
    paged = sessions |> Enum.drop(offset) |> Enum.take(limit)

    # Enrich with workspace_id for frontend navigation
    paged = enrich_with_workspace_ids(paged)

    json_response(conn, 200, %{
      sessions: paged,
      total: total,
      offset: offset,
      limit: limit
    })
  end

  defp enrich_with_workspace_ids(sessions) do
    paths =
      sessions
      |> Enum.map(&(&1[:workspace_path] || &1["workspace_path"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    path_to_id =
      if paths != [] do
        import Ecto.Query
        alias AIBrain.Data.Workspace

        Repo.all(from(w in Workspace, where: w.path in ^paths, select: {w.path, w.id}))
        |> Map.new()
      else
        %{}
      end

    Enum.map(sessions, fn s ->
      wp = s[:workspace_path] || s["workspace_path"]

      if wp && path_to_id[wp] do
        Map.put(s, :workspace_id, path_to_id[wp])
      else
        s
      end
    end)
  end

  defp sort_sessions(sessions, "created_at_asc"),
    do: Enum.sort_by(sessions, &(&1[:created_at] || &1["created_at"] || ""), :asc)

  defp sort_sessions(sessions, "created_at_desc"),
    do: Enum.sort_by(sessions, &(&1[:created_at] || &1["created_at"] || ""), :desc)

  defp sort_sessions(sessions, "title_asc"),
    do: Enum.sort_by(sessions, &String.downcase(&1[:title] || &1["title"] || ""), :asc)

  defp sort_sessions(sessions, "title_desc"),
    do: Enum.sort_by(sessions, &String.downcase(&1[:title] || &1["title"] || ""), :desc)

  defp sort_sessions(sessions, _),
    do: Enum.sort_by(sessions, &(&1[:updated_at] || &1["updated_at"] || ""), :desc)

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} when n >= 0 -> n
      _ -> default
    end
  end

  defp store,
    do: AIBrain.Config.session_store()

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
