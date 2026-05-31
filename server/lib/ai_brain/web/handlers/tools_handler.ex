defmodule AIBrain.Web.Handlers.ToolsHandler do
  import Plug.Conn
  alias AIBrain.Tool.Discovery

  def handle_list(conn) do
    tools = Discovery.list_tools()
    json_response(conn, 200, %{tools: tools})
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
