defmodule AIBrain.Planning.Collector do
  @moduledoc """
  Synthesizes task execution results into a coherent summary.

  Called after all tasks in a goal have been dispatched through
  the Task DAG Executor.
  """

  alias AIBrain.Data.{Goals, Tasks}

  @doc """
  Build a detailed report for a completed (or partially completed) goal.

  Returns a map with goal info, per-task results, and an overall summary.
  """
  def collect(goal_id) do
    with {:ok, goal} <- Goals.get(goal_id),
         tasks when is_list(tasks) <- Tasks.list_tasks(goal_id) do
      task_results =
        Enum.map(tasks, fn task ->
          %{
            id: task.id,
            title: task.title,
            status: task.status,
            output: task.output
          }
        end)

      completed = Enum.count(tasks, &(&1.status == "completed"))
      failed = Enum.count(tasks, &(&1.status == "failed"))
      pending = Enum.count(tasks, &(&1.status in ~w(pending assigned)))
      cancelled = Enum.count(tasks, &(&1.status == "cancelled"))

      summary =
        if tasks == [] do
          "No tasks were created for this goal."
        else
          "Goal '#{goal.title}': #{completed} completed, #{failed} failed, #{pending} pending, #{cancelled} cancelled."
        end

      {:ok,
       %{
         goal: %{id: goal.id, title: goal.title, status: goal.status, priority: goal.priority},
         tasks: task_results,
         stats: %{
           total: length(tasks),
           completed: completed,
           failed: failed,
           pending: pending,
           cancelled: cancelled
         },
         summary: summary
       }}
    else
      {:error, :not_found} -> {:error, :not_found}
      _ -> {:error, :unexpected_error}
    end
  end
end
