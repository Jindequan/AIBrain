defmodule AIBrain.Data.Runs do
  @moduledoc """
  CRUD operations for the unified `runs` table.
  Canonical storage for all agent executions.
  """

  import Ecto.Query

  alias AIBrain.Data.{Run, RunContextRef, RunContextRefs, RunSteps}
  alias AIBrain.Repo

  @doc "List runs with optional source, context ref, status, mode, phase, and limit filters"
  def list_runs(opts \\ []) do
    query = from(r in Run, order_by: [desc: r.inserted_at])

    query =
      case Keyword.get(opts, :source_type) do
        nil -> query
        source_type -> from(r in query, where: r.source_type == ^source_type)
      end

    query =
      case Keyword.get(opts, :source_id) do
        nil -> query
        source_id -> from(r in query, where: r.source_id == ^source_id)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status when is_binary(status) -> from(r in query, where: r.status == ^status)
        statuses when is_list(statuses) -> from(r in query, where: r.status in ^statuses)
      end

    query =
      case Keyword.get(opts, :mode) do
        nil -> query
        mode -> from(r in query, where: r.mode == ^mode)
      end

    query =
      case Keyword.get(opts, :phase) do
        nil -> query
        phase -> from(r in query, where: r.phase == ^phase)
      end

    query = maybe_filter_ref(query, Keyword.get(opts, :ref_type), Keyword.get(opts, :ref_id))

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> from(r in query, limit: ^limit)
      end

    Repo.all(query)
  end

  def list_runs_for_ref(ref_type, ref_id, opts \\ []) do
    opts
    |> Keyword.put(:ref_type, ref_type)
    |> Keyword.put(:ref_id, ref_id)
    |> list_runs()
  end

  @doc "Get a single run by ID"
  def get_run(id) do
    case Repo.get(Run, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @doc "Create a new run"
  def create_run(attrs) when is_map(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a run's fields by ID"
  def update_run(id, attrs) do
    case get_run(id) do
      {:ok, run} -> run |> Run.changeset(attrs) |> Repo.update()
      error -> error
    end
  end

  @terminal_statuses ~w(completed completed_with_warnings failed cancelled)

  @doc """
  Atomically transition a run to a new status, only if it is NOT already in a
  terminal state. Prevents lost-update races when two callers concurrently
  complete/fail/suspend the same run.

  Returns `{:ok, count}` where count is 1 (transitioned) or 0 (already terminal).
  """
  def transition_not_terminal(id, status, extra_attrs \\ %{}) do
    {count, _} =
      Repo.update_all(
        from(r in Run,
          where: r.id == ^id and r.status not in ^@terminal_statuses
        ),
        set: [status: status] ++ Map.to_list(extra_attrs)
      )

    {:ok, count}
  end

  @doc """
  Atomically transition a run from a specific status to a new status.
  Used for pending→running where we must not transition if already terminal.

  Returns `{:ok, count}` where count is 1 (transitioned) or 0 (wrong current status).
  """
  def transition_from(id, from_status, to_status, extra_attrs \\ %{}) do
    {count, _} =
      Repo.update_all(
        from(r in Run,
          where: r.id == ^id and r.status == ^from_status
        ),
        set: [status: to_status] ++ Map.to_list(extra_attrs)
      )

    {:ok, count}
  end

  @doc """
  Load full decision context for a run.
  Takes run_id → returns map with goal, task, progress, output.
  Used by Proxy and other downstream consumers.
  """
  def load_context(run_id) do
    with {:ok, run} <- get_run(run_id) do
      refs = RunContextRefs.list_for_run(run.id)
      steps = RunSteps.list_for_run(run.id)
      goal_id = ref_id(refs, "goal") || if(run.source_type == "goal", do: run.source_id)
      task_id = ref_id(refs, "task") || if(run.source_type == "task", do: run.source_id)

      goal =
        case goal_id do
          gid when is_binary(gid) ->
            try do
              case AIBrain.Data.Goals.get(gid) do
                {:ok, goal} -> goal
                _ -> nil
              end
            rescue
              _ -> nil
            end

          _ ->
            nil
        end

      task =
        case task_id do
          tid when is_binary(tid) ->
            try do
              case AIBrain.Data.Tasks.get_task(tid) do
                {:ok, task} -> task
                _ -> nil
              end
            rescue
              _ -> nil
            end

          _ ->
            nil
        end

      %{
        run_id: run.id,
        source_type: run.source_type,
        source_id: run.source_id,
        status: run.status,
        phase: run.phase,
        mode: run.mode,
        objective: run.objective,
        goal_id: goal_id,
        goal_title: goal && goal.title,
        goal_status: goal && goal.status,
        task_id: task_id,
        task_title: (task && task.title) || run.title,
        task_output: run.output_summary || "",
        output_path: run.output_path,
        messages_path: run.messages_path,
        context_refs: Enum.map(refs, &Map.take(&1, [:ref_type, :ref_id, :role, :metadata])),
        steps:
          Enum.map(
            steps,
            &Map.take(&1, [
              :step_index,
              :phase,
              :status,
              :kind,
              :title,
              :summary,
              :output_path,
              :error
            ])
          )
      }
    end
  end

  @doc "Cancel a run (set status to cancelled)"
  def cancel_run(id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    update_run(id, %{status: "cancelled", completed_at: now})
  end

  @doc "List child runs by parent_run_id (delegation chain)"
  def list_child_runs(parent_run_id) do
    query =
      from(r in Run,
        where: r.parent_run_id == ^parent_run_id,
        order_by: [asc: r.inserted_at]
      )

    Repo.all(query)
  end

  defp ref_id(refs, type) do
    refs
    |> Enum.find(fn ref -> ref.ref_type == type end)
    |> case do
      nil -> nil
      ref -> ref.ref_id
    end
  end

  defp maybe_filter_ref(query, nil, nil), do: query

  defp maybe_filter_ref(query, ref_type, ref_id) when is_binary(ref_type) and is_binary(ref_id) do
    from(r in query,
      join: ref in RunContextRef,
      on: ref.run_id == r.id,
      where: ref.ref_type == ^ref_type and ref.ref_id == ^ref_id,
      distinct: true
    )
  end

  defp maybe_filter_ref(query, _ref_type, _ref_id), do: query
end
