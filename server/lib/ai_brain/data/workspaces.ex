defmodule AIBrain.Data.Workspaces do
  @moduledoc """
  CRUD for workspaces table.

  Workspaces are purely for frontend listing — no FK relationships to other tables.
  Rows are auto-created when a session is created with a workspace_path.
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.Workspace

  @doc "List all workspaces"
  def list do
    Repo.all(from(w in Workspace, order_by: [asc: w.name]))
  end

  @doc "Get a workspace by ID"
  def get(id) do
    case Repo.get(Workspace, id) do
      nil -> {:error, :not_found}
      ws -> {:ok, ws}
    end
  end

  @doc "Find a workspace by path"
  def get_by_path(path) do
    case Repo.get_by(Workspace, path: path) do
      nil -> {:error, :not_found}
      ws -> {:ok, ws}
    end
  end

  @doc """
  Ensure a workspace record exists for the given path.
  Returns the existing or newly created workspace.
  """
  def ensure(path) when is_binary(path) and path != "" do
    case get_by_path(path) do
      {:ok, ws} ->
        {:ok, ws}

      {:error, :not_found} ->
        name = derive_name(path)
        id = "ws-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))

        %Workspace{}
        |> Workspace.changeset(%{id: id, name: name, path: path})
        |> Repo.insert()

        # Return the existing or newly created workspace
        get_by_path(path)
    end
  end

  def ensure(_), do: {:error, :invalid_path}

  defp derive_name(path) do
    path
    |> String.trim_trailing("/")
    |> Path.split()
    |> List.last()
    |> Kernel.||("Workspace")
  end
end
