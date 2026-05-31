defmodule AIBrain.Data.Goals do
  @moduledoc """
  CRUD operations for goals.
  """

  require Logger
  alias AIBrain.Repo
  alias AIBrain.Data.Goal

  @doc "Create a new goal"
  def create(attrs) when is_map(attrs) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, goal} ->
        Logger.info("Goal created: #{goal.title} (#{goal.id})")
        {:ok, goal}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc "List goals with optional filters"
  def list(opts \\ []) do
    import Ecto.Query

    parent_id = Keyword.get(opts, :parent_id)
    status = Keyword.get(opts, :status)
    workspace_path = Keyword.get(opts, :workspace_path)

    query = from(g in Goal, order_by: [asc: g.priority, asc: g.title])

    query =
      if Keyword.has_key?(opts, :parent_id) do
        if parent_id == nil do
          where(query, [g], is_nil(g.parent_id))
        else
          where(query, [g], g.parent_id == ^parent_id)
        end
      else
        query
      end

    query =
      if status do
        where(query, [g], g.status == ^status)
      else
        query
      end

    query =
      if workspace_path do
        where(query, [g], g.workspace_path == ^workspace_path)
      else
        query
      end

    {:ok, Repo.all(query)}
  end

  @doc "Get a single goal by ID"
  def get(id) do
    case Repo.get(Goal, id) do
      nil -> {:error, :not_found}
      goal -> {:ok, goal}
    end
  end

  @doc "Update a goal"
  def update(id, attrs) when is_map(attrs) do
    case Repo.get(Goal, id) do
      nil ->
        {:error, :not_found}

      goal ->
        goal
        |> Goal.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, inspect(changeset.errors)}
        end
    end
  end

  @doc "Delete a goal"
  def delete(id) do
    case Repo.get(Goal, id) do
      nil ->
        {:error, :not_found}

      goal ->
        Repo.delete(goal)
        :ok
    end
  end

  @doc "Update a goal's status"
  def update_status(id, status) when is_binary(status) do
    case Repo.get(Goal, id) do
      nil ->
        {:error, :not_found}

      goal ->
        goal
        |> Goal.changeset(%{status: status})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, inspect(changeset.errors)}
        end
    end
  end
end
