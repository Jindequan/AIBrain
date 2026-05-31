defmodule AIBrain.Planning.Executor do
  @moduledoc """
  Task DAG Executor — executes tasks in topological wave order.

  Tasks with no dependencies execute first, then tasks that depend on them,
  and so on. Each "wave" contains tasks that can run in parallel.
  """

  alias AIBrain.Data.{Goals, Tasks}

  @doc """
  Compute execution waves from a list of tasks.

  Returns a list of lists, where each inner list is a wave of tasks
  that can be executed in parallel. Tasks in wave N depend only on
  tasks in waves 0..N-1.

  ## Example

      iex> tasks = [
      ...>   %{id: "a", title: "Root", depends_on: []},
      ...>   %{id: "b", title: "Mid", depends_on: ["a"]},
      ...>   %{id: "c", title: "Leaf", depends_on: ["b"]}
      ...> ]
      iex> Executor.compute_waves(tasks)
      [[%{id: "a", ...}], [%{id: "b", ...}], [%{id: "c", ...}]]
  """
  def compute_waves(tasks) when is_list(tasks) do
    # Build a map of id -> task for quick lookup
    task_map = Map.new(tasks, fn t -> {t.id, t} end)

    # Build adjacency list: task_id -> [dependency_ids]
    dep_map = Map.new(tasks, fn t -> {t.id, t.depends_on || []} end)

    # Build reverse adjacency: task_id -> [dependents]
    rev_dep_map = build_reverse_dependencies(dep_map)

    # Compute waves using Kahn's algorithm variant
    compute_waves_kahn(task_map, dep_map, rev_dep_map, MapSet.new(tasks, & &1.id))
  end

  @doc """
  Execute all tasks for a goal in wave order.

  Loads the goal and its tasks, computes execution waves,
  and returns the goal with all tasks. This is a synchronous
  execution that processes the DAG structure but doesn't
  actually run task logic (task execution is handled elsewhere).

  Returns `{:ok, result}` where result contains the goal and tasks,
  or `{:error, reason}`.
  """
  def execute(goal_id) do
    with {:ok, goal} <- Goals.get(goal_id),
         tasks when is_list(tasks) <- Tasks.list_tasks(goal_id) do
      waves = compute_waves(tasks)

      result = %{
        goal: %{
          id: goal.id,
          title: goal.title,
          status: goal.status,
          priority: goal.priority
        },
        tasks: tasks,
        waves: waves
      }

      {:ok, result}
    else
      {:error, :not_found} -> {:error, :goal_not_found}
      _ -> {:error, :unexpected_error}
    end
  end

  # ── Private: Wave Computation (Kahn's Algorithm) ─────────────────────────────

  defp compute_waves_kahn(task_map, dep_map, rev_dep_map, remaining_ids) do
    # Find tasks with no dependencies (in-degree = 0)
    ready_ids =
      Enum.filter(remaining_ids, fn id ->
        deps = MapSet.new(dep_map[id] || [])
        MapSet.intersection(deps, remaining_ids) |> MapSet.size() == 0
      end)

    if ready_ids == [] do
      # Either done or cycle detected
      if MapSet.size(remaining_ids) == 0 do
        []
      else
        # Cycle detected — return remaining as one wave (best effort)
        [Enum.map(remaining_ids, fn id -> task_map[id] end)]
      end
    else
      # Build current wave from ready tasks
      current_wave = Enum.map(ready_ids, fn id -> task_map[id] end)

      # Remove ready tasks from remaining set
      new_remaining = MapSet.difference(remaining_ids, MapSet.new(ready_ids))

      # Remove ready tasks from dependency maps for next iteration
      new_rev_dep_map =
        Enum.reduce(ready_ids, rev_dep_map, fn ready_id, acc ->
          # Remove ready_id from all dependency lists
          Map.new(acc, fn {task_id, deps} ->
            {task_id, Enum.reject(deps, &(&1 == ready_id))}
          end)
        end)

      # Recursively compute next waves
      [current_wave | compute_waves_kahn(task_map, dep_map, new_rev_dep_map, new_remaining)]
    end
  end

  defp build_reverse_dependencies(dep_map) do
    # Build task_id -> [tasks that depend on it]
    Enum.reduce(dep_map, %{}, fn {task_id, deps}, acc ->
      Enum.reduce(deps, acc, fn dep_id, inner_acc ->
        Map.update(inner_acc, dep_id, [task_id], fn existing -> [task_id | existing] end)
      end)
    end)
  end
end
