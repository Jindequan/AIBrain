defmodule AIBrain.Data.Artifacts do
  @moduledoc """
  CRUD operations for Artifacts.

  Artifacts are task-level deliverables, not file-level operation logs.
  See `AIBrain.Data.Artifact` for the full design rationale.
  """

  require Logger

  alias AIBrain.Repo
  alias AIBrain.Data.Artifact

  @doc "Create a new artifact"
  def create(attrs) when is_map(attrs) do
    %Artifact{}
    |> Artifact.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, artifact} ->
        Logger.info("Artifact created: #{artifact.title} (#{artifact.kind})")
        {:ok, artifact}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc "List artifacts with optional filters"
  def list(opts \\ []) do
    import Ecto.Query

    run_id = Keyword.get(opts, :run_id)
    kind = Keyword.get(opts, :kind)

    query = from(a in Artifact, order_by: [desc: a.inserted_at])
    query = maybe_filter(query, :run_id, run_id)
    query = maybe_filter(query, :kind, kind)

    {:ok, Repo.all(query)}
  end

  @doc "List all artifacts for a given run ID."
  def list_by_run(run_id) when is_binary(run_id) do
    import Ecto.Query

    {:ok,
     Repo.all(from(a in Artifact, where: a.run_id == ^run_id, order_by: [desc: a.inserted_at]))}
  end

  @doc "Get a single artifact by ID"
  def get(id) do
    case Repo.get(Artifact, id) do
      nil -> {:error, :not_found}
      artifact -> {:ok, artifact}
    end
  end

  @doc "Update an artifact"
  def update(id, attrs) when is_map(attrs) do
    case Repo.get(Artifact, id) do
      nil ->
        {:error, :not_found}

      artifact ->
        artifact
        |> Artifact.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, inspect(changeset.errors)}
        end
    end
  end

  @doc "Delete an artifact"
  def delete(id) do
    case Repo.get(Artifact, id) do
      nil ->
        {:error, :not_found}

      artifact ->
        Repo.delete(artifact)
        :ok
    end
  end

  defp maybe_filter(query, _key, nil), do: query

  defp maybe_filter(query, key, value) do
    import Ecto.Query
    where(query, [a], field(a, ^key) == ^value)
  end
end
