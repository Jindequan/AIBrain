defmodule AIBrain.Data.ContextLinks do
  @moduledoc """
  CRUD operations for Context Links.
  """

  require Logger

  alias AIBrain.Repo
  alias AIBrain.Data.ContextLink

  @doc "List context links with optional filters"
  def list(opts \\ []) do
    import Ecto.Query

    context_type = Keyword.get(opts, :context_type)
    owner_type = Keyword.get(opts, :owner_type)
    owner_id = Keyword.get(opts, :owner_id)

    query = from(c in ContextLink, order_by: [desc: c.inserted_at])

    query =
      if context_type, do: from(c in query, where: c.context_type == ^context_type), else: query

    query = if owner_type, do: from(c in query, where: c.owner_type == ^owner_type), else: query
    query = if owner_id, do: from(c in query, where: c.owner_id == ^owner_id), else: query

    {:ok, Repo.all(query)}
  end

  @doc "Get a single context link by ID"
  def get(id) do
    case Repo.get(ContextLink, id) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  @doc "Create a new context link"
  def create(attrs) when is_map(attrs) do
    %ContextLink{}
    |> ContextLink.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, link} ->
        Logger.info("ContextLink created: #{link.id}")
        {:ok, link}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc "Update a context link"
  def update(id, attrs) when is_map(attrs) do
    case Repo.get(ContextLink, id) do
      nil ->
        {:error, :not_found}

      link ->
        link
        |> ContextLink.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, inspect(changeset.errors)}
        end
    end
  end

  @doc "Delete a context link"
  def delete(id) do
    case Repo.get(ContextLink, id) do
      nil ->
        {:error, :not_found}

      link ->
        Repo.delete(link)
        :ok
    end
  end
end
