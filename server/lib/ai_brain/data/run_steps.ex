defmodule AIBrain.Data.RunSteps do
  @moduledoc """
  Helpers for run step auditing.
  """

  import Ecto.Query

  alias AIBrain.Data.RunStep
  alias AIBrain.Repo

  def create(attrs) when is_map(attrs) do
    %RunStep{}
    |> RunStep.changeset(attrs)
    |> Repo.insert()
  end

  def complete(id, attrs \\ %{}) do
    case Repo.get(RunStep, id) do
      nil ->
        {:error, :not_found}

      step ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        attrs = normalize_attrs(attrs)
        attrs = Map.merge(%{status: "completed", completed_at: now}, attrs)
        step |> RunStep.changeset(attrs) |> Repo.update()
    end
  end

  def fail(id, error, attrs \\ %{}) do
    case Repo.get(RunStep, id) do
      nil ->
        {:error, :not_found}

      step ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        attrs = normalize_attrs(attrs)
        attrs = Map.merge(%{status: "failed", error: error, completed_at: now}, attrs)
        step |> RunStep.changeset(attrs) |> Repo.update()
    end
  end

  def cancel_open(run_id, summary \\ "Run cancelled.") do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(
      from(s in RunStep,
        where: s.run_id == ^run_id,
        where: s.status in ["pending", "running", "waiting"]
      ),
      set: [status: "cancelled", summary: summary, completed_at: now]
    )
  end

  def wait(run_id, kind, attrs \\ %{}) do
    attrs =
      attrs
      |> normalize_attrs()
      |> Map.put(:run_id, run_id)
      |> Map.put(:step_index, next_index(run_id))
      |> Map.put(:phase, "waiting")
      |> Map.put(:status, "waiting")
      |> Map.put(:kind, to_string(kind))
      |> Map.put_new(:title, "Waiting")

    create(attrs)
  end

  def resolve_wait(run_id, resume_token, attrs \\ %{}) do
    case get_waiting_by_token(run_id, resume_token) do
      nil -> {:error, :not_found}
      step -> complete(step.id, attrs)
    end
  end

  def claim_wait(resume_token) when is_binary(resume_token) do
    Repo.transaction(fn ->
      {count, _} =
        Repo.update_all(
          from(s in RunStep,
            where: s.status == "waiting",
            where: fragment("json_extract(?, '$.resume_token') = ?", s.metadata, ^resume_token)
          ),
          set: [status: "running"]
        )

      case count do
        0 ->
          case get_by_resume_token(resume_token) do
            nil -> Repo.rollback(:not_found)
            _step -> Repo.rollback(:already_claimed)
          end

        _ ->
          case get_by_resume_token(resume_token, "running") do
            nil -> Repo.rollback(:not_found)
            step -> step
          end
      end
    end)
    |> case do
      {:ok, step} -> {:ok, step}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_resume_token(resume_token, status \\ nil) do
    query =
      from(s in RunStep,
        where: fragment("json_extract(?, '$.resume_token') = ?", s.metadata, ^resume_token),
        order_by: [desc: s.inserted_at],
        limit: 1
      )

    query =
      case status do
        nil -> query
        status -> from(s in query, where: s.status == ^status)
      end

    Repo.one(query)
  end

  def list_resumable do
    Repo.all(
      from(s in RunStep,
        where: s.status == "running",
        where: not is_nil(fragment("json_extract(?, '$.resume_token')", s.metadata)),
        order_by: [asc: s.inserted_at]
      )
    )
  end

  def next_index(run_id) do
    query =
      from(s in RunStep,
        where: s.run_id == ^run_id,
        select: max(s.step_index)
      )

    case Repo.one(query) do
      nil -> 0
      n -> n + 1
    end
  end

  def list_for_run(run_id) do
    Repo.all(
      from(s in RunStep,
        where: s.run_id == ^run_id,
        order_by: [asc: s.step_index]
      )
    )
  end

  def latest_running(run_id, kind \\ nil) do
    query =
      from(s in RunStep,
        where: s.run_id == ^run_id,
        where: s.status == "running",
        order_by: [desc: s.step_index],
        limit: 1
      )

    query =
      case kind do
        nil -> query
        kind -> from(s in query, where: s.kind == ^to_string(kind))
      end

    Repo.one(query)
  end

  defp get_waiting_by_token(run_id, resume_token) do
    Repo.one(
      from(s in RunStep,
        where: s.run_id == ^run_id,
        where: s.phase == "waiting",
        where: s.status in ["waiting", "running"],
        where: fragment("json_extract(?, '$.resume_token') = ?", s.metadata, ^resume_token),
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(_attrs), do: %{}
end
