defmodule AIBrain.Web.Handlers.ProxyHandler do
  @moduledoc """
  HTTP handler for proxy status and toggle.
  """

  import Plug.Conn
  alias AIBrain.Data.Users

  def handle_status(conn) do
    {:ok, proxy} = Users.get_proxy()

    json(conn, 200, %{
      active: proxy.active || false,
      name: proxy.name
    })
  end

  def handle_toggle(conn, params) do
    activate = Map.get(params, "active", true)

    case Users.update(%{active: activate}, "proxy") do
      {:ok, user} ->
        AIBrain.Proxy.set_active(activate)
        json(conn, 200, %{active: user.active})

      {:error, reason} ->
        json(conn, 422, %{error: reason})
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
