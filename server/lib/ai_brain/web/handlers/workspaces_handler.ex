defmodule AIBrain.Web.Handlers.WorkspacesHandler do
  import Plug.Conn

  alias AIBrain.Data.Workspaces

  def handle_list(conn) do
    workspaces = Workspaces.list()

    json_response(conn, 200, %{
      workspaces: workspaces
    })
  end

  def handle_get(conn, id) do
    case Workspaces.get(id) do
      {:ok, ws} ->
        json_response(conn, 200, %{workspace: ws})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Workspace not found"})
    end
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
