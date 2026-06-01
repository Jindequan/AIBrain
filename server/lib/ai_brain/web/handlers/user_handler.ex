defmodule AIBrain.Web.Handlers.UserHandler do
  @moduledoc """
  HTTP handler for user management.
  Supports multiple users (main user, proxy, contacts).
  """

  import Plug.Conn
  alias AIBrain.Data.Users

  def handle_list(conn) do
    users = Users.list()
    json(conn, 200, %{users: users})
  end

  def handle_get(conn) do
    {:ok, user} = Users.get()
    json(conn, 200, user)
  end

  def handle_get_by_id(conn, id) do
    case Users.get_by_id(id) do
      {:ok, user} -> json(conn, 200, user)
      {:error, :not_found} -> json(conn, 404, %{error: "User not found"})
    end
  end

  def handle_update(conn, params) do
    update_attrs =
      Map.take(params, ["name", "bio", "active", "profile", "preferences"])
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    result =
      case Map.get(params, "id") do
        nil ->
          Users.update(update_attrs, "user")

        id ->
          Users.update_by_id(id, update_attrs)
      end

    case result do
      {:ok, user} -> json(conn, 200, user)
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_create(conn, params) do
    attrs =
      Map.take(params, ["id", "name", "bio", "role", "active", "profile", "preferences"])
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    case Users.create(attrs) do
      {:ok, user} -> json(conn, 201, user)
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_delete(conn, id) do
    case Users.delete(id) do
      :ok -> json(conn, 200, %{message: "Deleted"})
      {:error, :cannot_delete_default} -> json(conn, 422, %{error: "Cannot delete default users"})
      {:error, :not_found} -> json(conn, 404, %{error: "User not found"})
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
