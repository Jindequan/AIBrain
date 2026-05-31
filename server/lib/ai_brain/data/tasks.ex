defmodule AIBrain.Data.Tasks do
  @moduledoc """
  CRUD operations for Tasks.
  """

  require Logger
  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.{Goal, Task}

  @output_summary_limit 1_000

  @doc "List all tasks across all goals, newest first. Optional workspace_path filter (via goal)."
  def list_all_tasks(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)

    Task
    |> join(:left, [t], g in assoc(t, :goal))
    |> preload([t, _g], [:goal])
    |> then(fn query ->
      if workspace_path,
        do: where(query, [t, g], g.workspace_path == ^workspace_path),
        else: query
    end)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  @doc "List tasks for a goal"
  def list_tasks(goal_id, opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)

    Task
    |> where([t], t.goal_id == ^goal_id)
    |> join(:left, [t], g in assoc(t, :goal))
    |> then(fn query ->
      if workspace_path,
        do: where(query, [t, g], g.workspace_path == ^workspace_path),
        else: query
    end)
    |> order_by([t], asc: t.id)
    |> Repo.all()
  end

  @doc "Get a single task, raises if not found"
  def get_task!(id), do: Repo.get!(Task, id)

  @doc "Get a single task"
  def get_task(id) do
    case Repo.get(Task, id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc "Create a task"
  def create_task(attrs \\ %{}) do
    changeset =
      %Task{}
      |> Task.changeset(attrs)
      |> validate_goal_exists()

    Repo.insert(changeset)
  end

  @doc "Update a task"
  def update_task(%Task{} = task, attrs) do
    changeset =
      task
      |> Task.changeset(attrs)
      |> validate_goal_exists()

    Repo.update(changeset)
  end

  @doc "Delete a task"
  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc "Build a changeset for a task"
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc "List tasks for a goal with a specific status"
  def list_tasks_by_status(goal_id, status) do
    Task
    |> where([t], t.goal_id == ^goal_id and t.status == ^status)
    |> order_by([t], asc: t.id)
    |> Repo.all()
  end

  @doc "Count tasks grouped by status for a goal"
  def count_tasks_by_status(goal_id) do
    Task
    |> where([t], t.goal_id == ^goal_id)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Enum.into(%{
      "pending" => 0,
      "assigned" => 0,
      "in_progress" => 0,
      "running" => 0,
      "completed" => 0,
      "failed" => 0,
      "cancelled" => 0
    })
  end

  @doc "Update a task's status"
  def update_task_status(%Task{} = task, status) do
    task
    |> Task.changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Update a task status with a file-backed output body.

  The task row keeps a short summary in `output` and stores the full body on
  disk. When the task is linked to a run, the canonical run output file is used;
  otherwise a task-local output file is created under the configured data dir.
  """
  def update_task_result(%Task{} = task, status, output) when is_binary(output) do
    {summary, metadata} = persist_output(task, output)

    update_task(task, %{
      status: status,
      output: summary,
      metadata: Map.merge(task.metadata || %{}, metadata)
    })
  end

  def update_task_result(%Task{} = task, status, output) do
    update_task_result(task, status, inspect(output))
  end

  def task_output_path(%Task{run_id: run_id}) when is_binary(run_id) and run_id != "" do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join([data_dir, "runs", run_id, "output.md"])
  end

  def task_output_path(%Task{id: id}) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join([data_dir, "task_outputs", id, "output.md"])
  end

  @doc "Fetch multiple tasks by their IDs"
  def list_by_ids(task_ids) when is_list(task_ids) do
    Task
    |> where([t], t.id in ^task_ids)
    |> Repo.all()
  end

  @doc "Given a task's depends_on, return any of those dependencies that are not yet completed"
  def list_incomplete_dependencies(%Task{depends_on: deps}) when deps in [nil, []], do: []

  def list_incomplete_dependencies(%Task{depends_on: deps}) do
    Task
    |> where([t], t.id in ^deps and t.status != "completed")
    |> Repo.all()
  end

  def list_incomplete_dependencies(_), do: []

  @doc "List tasks ready to dispatch: pending status, all deps completed, ordered by priority desc."
  def list_pending_dispatchable do
    pending =
      Task
      |> where([t], t.status == "pending")
      |> order_by([t], desc: t.priority)
      |> Repo.all()

    case pending do
      [] ->
        []

      tasks ->
        all_dep_ids =
          tasks
          |> Enum.flat_map(fn t -> t.depends_on || [] end)
          |> Enum.uniq()

        incomplete_ids =
          if all_dep_ids == [] do
            MapSet.new()
          else
            Task
            |> where([t], t.id in ^all_dep_ids and t.status != "completed")
            |> select([t], t.id)
            |> Repo.all()
            |> MapSet.new()
          end

        Enum.filter(tasks, fn t ->
          Enum.all?(t.depends_on || [], &(not MapSet.member?(incomplete_ids, &1)))
        end)
    end
  end

  @doc "Get task by its associated run_id"
  def get_by_run_id(run_id) do
    case Repo.get_by(Task, run_id: run_id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc "Atomically mark task as running with its run_id. Fails if task is not pending."
  def update_run(task_id, run_id) do
    case get_task(task_id) do
      {:ok, %{status: "pending"} = task} ->
        update_task(task, %{status: "running", run_id: run_id})

      {:ok, _task} ->
        {:error, :not_pending}

      error ->
        error
    end
  end

  @doc """
  Persist task ordering for a goal.

  The current schema has no dedicated position column, so ordering metadata is
  stored in each task's metadata under `"position"`. Unknown task ids are
  ignored only when the requested order is empty; otherwise all ids must belong
  to the goal to avoid silently corrupting a board order.
  """
  def reorder_tasks(goal_id, ordered_task_ids) when is_list(ordered_task_ids) do
    case Repo.get(Goal, goal_id) do
      nil ->
        {:error, :not_found}

      _goal ->
        tasks =
          Task
          |> where([t], t.goal_id == ^goal_id)
          |> Repo.all()

        task_by_id = Map.new(tasks, &{&1.id, &1})

        cond do
          ordered_task_ids == [] ->
            :ok

          Enum.any?(ordered_task_ids, &(not Map.has_key?(task_by_id, &1))) ->
            {:error, :invalid_task_ids}

          true ->
            Repo.transaction(fn ->
              ordered_task_ids
              |> Enum.with_index()
              |> Enum.each(fn {task_id, index} ->
                task = Map.fetch!(task_by_id, task_id)
                metadata = task.metadata || %{}
                update_task(task, %{metadata: Map.put(metadata, "position", index)})
              end)
            end)
            |> case do
              {:ok, _} -> :ok
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  defp validate_goal_exists(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :goal_id) do
      nil ->
        changeset

      goal_id ->
        if Repo.exists?(from(g in Goal, where: g.id == ^goal_id)) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :goal_id, "does not exist")
        end
    end
  end

  defp persist_output(%Task{} = task, output) do
    path = task_output_path(task)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, output)

    summary = summarize_output(output) |> String.slice(0, @output_summary_limit)

    metadata = %{
      "output_path" => path,
      "output_bytes" => byte_size(output),
      "output_truncated" => byte_size(output) > byte_size(summary)
    }

    {summary, metadata}
  end

  defp summarize_output(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 1_000)
  end

  defp summarize_output(_), do: ""
end
