defmodule AIBrain.Data.Users do
  @moduledoc """
  CRUD for user identities.
  Supports the main human user (role: "user") and the proxy user (role: "proxy").
  """

  require Logger
  alias AIBrain.Repo
  alias AIBrain.Data.User

  import Ecto.Query

  @user_id "user-default"
  @proxy_id "proxy-default"

  def default_user_id, do: @user_id
  def default_proxy_id, do: @proxy_id

  @doc "Get the main human user. Creates a default one if it doesn't exist."
  def get do
    case Repo.one(from(u in User, where: u.role == "user", order_by: [asc: u.id], limit: 1)) do
      nil ->
        {:ok, user} = create_default()
        {:ok, user}

      user ->
        {:ok, user}
    end
  end

  @doc "Get the proxy user (role: 'proxy'). Creates a disabled one if it doesn't exist."
  def get_proxy do
    case Repo.one(from(u in User, where: u.role == "proxy", order_by: [asc: u.id], limit: 1)) do
      nil ->
        {:ok, user} = create_proxy()
        {:ok, user}

      user ->
        {:ok, user}
    end
  end

  @doc "List all users."
  def list do
    Repo.all(from(u in User, order_by: [asc: u.role, asc: u.id]))
  end

  @doc "Create a new user."
  def create(attrs) when is_map(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        Logger.info("User created: #{user.id}")
        {:ok, user}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc "Delete a user by ID. Cannot delete the default users."
  def delete(id) when id in [@user_id, @proxy_id] do
    {:error, :cannot_delete_default}
  end

  def delete(id) do
    case Repo.get(User, id) do
      nil ->
        {:error, :not_found}

      user ->
        Repo.delete(user)
        Logger.info("User deleted: #{id}")
        :ok
    end
  end

  @doc "Get user by ID."
  def get_by_id(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc "Update user attributes by role."
  def update(attrs, role \\ "user") when is_map(attrs) do
    query = fn ->
      case role do
        "proxy" -> get_proxy()
        _ -> get()
      end
    end

    {:ok, user} = query.()

    user
    |> User.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, user} ->
        Logger.info("User updated: #{user.name} (role: #{user.role})")
        {:ok, user}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  defp create_default do
    %User{}
    |> User.changeset(%{id: @user_id, name: "Me", role: "user", active: true})
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        Logger.info("Default user created: #{user.id}")
        {:ok, user}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  defp create_proxy do
    %User{}
    |> User.changeset(%{id: @proxy_id, name: "Proxy", role: "proxy", active: false})
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        Logger.info("Proxy user created: #{user.id} (inactive by default)")
        {:ok, user}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end
end
