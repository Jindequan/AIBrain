defmodule AIBrain.Web.Handlers.SearchHandler do
  require Logger
  import Plug.Conn
  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.{Goal, Task, Artifact}

  def handle_global_search(conn) do
    q = conn.params["q"] || ""

    if q == "" do
      json(conn, 200, %{results: [], total: 0})
    else
      query = String.downcase(q)

      results =
        search_sessions(query) ++
          search_goals(query) ++
          search_tasks(query) ++
          search_artifacts(query)

      json(conn, 200, %{results: results, total: length(results)})
    end
  rescue
    e ->
      Logger.error("Global search failed: #{inspect(e)}")
      json(conn, 200, %{results: [], total: 0})
  end

  defp search_sessions(query) do
    session_store = AIBrain.Config.session_store()
    sessions = session_store.list_sessions(session_store)

    sessions
    |> Enum.filter(fn s ->
      title = s[:title] || s["title"] || ""
      String.contains?(String.downcase(title), query)
    end)
    |> Enum.map(fn s ->
      id = s[:session_id] || s["session_id"]
      title = s[:title] || s["title"] || id

      %{
        type: "session",
        id: id,
        title: title,
        subtitle: s[:workspace_path] || s["workspace_path"],
        status: s[:status] || s["status"],
        url: "/chat/#{id}"
      }
    end)
    |> Enum.take(10)
  end

  defp search_goals(query) do
    like = "%#{query}%"

    Repo.all(
      from(g in Goal,
        where:
          like(fragment("LOWER(?)", g.title), ^like) or
            like(fragment("LOWER(?)", g.description), ^like),
        limit: 5,
        order_by: [asc: g.priority]
      )
    )
    |> Enum.map(fn g ->
      %{
        type: "goal",
        id: g.id,
        title: g.title,
        subtitle: truncate(g.description, 80),
        status: g.status,
        url: "/goals"
      }
    end)
  end

  defp search_tasks(query) do
    like = "%#{query}%"

    Repo.all(
      from(t in Task,
        where:
          like(fragment("LOWER(?)", t.title), ^like) or
            like(fragment("LOWER(?)", t.description), ^like),
        limit: 5,
        order_by: [desc: t.updated_at]
      )
    )
    |> Enum.map(fn t ->
      %{
        type: "task",
        id: t.id,
        title: t.title,
        subtitle: truncate(t.description, 80),
        status: t.status,
        url: "/tasks"
      }
    end)
  end

  defp search_artifacts(query) do
    like = "%#{query}%"

    Repo.all(
      from(a in Artifact,
        where:
          like(fragment("LOWER(?)", a.title), ^like) or
            like(fragment("LOWER(?)", a.kind), ^like) or
            like(fragment("LOWER(?)", a.content), ^like),
        limit: 5,
        order_by: [desc: a.inserted_at]
      )
    )
    |> Enum.map(fn a ->
      %{
        type: "artifact",
        id: a.id,
        title: a.title || a.kind,
        subtitle: truncate(a.content, 80),
        kind: a.kind,
        url: "/artifacts"
      }
    end)
  end

  defp truncate(nil, _max), do: nil

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
