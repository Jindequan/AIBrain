defmodule AIBrain.Web.Handlers.GoalTasksHandler do
  @moduledoc """
  HTTP handler for CRUD operations on Goal Tasks.

  All functions receive a Plug.Conn and return a Plug.Conn.
  """

  import Plug.Conn
  import Ecto.Changeset, only: [traverse_errors: 2]
  require Logger

  alias AIBrain.AgentRuntime.RunLifecycle
  alias AIBrain.Data.Tasks

  def handle_list(conn, params) do
    goal_id = params["goal_id"]
    workspace_path = params["workspace_path"]
    opts = if workspace_path, do: [workspace_path: workspace_path], else: []
    tasks = Tasks.list_tasks(goal_id, opts) |> Enum.map(&serialize_task/1)
    json(conn, 200, %{tasks: tasks})
  end

  def handle_list_all(conn) do
    workspace_path = conn.params["workspace_path"]
    opts = if workspace_path, do: [workspace_path: workspace_path], else: []
    tasks = Tasks.list_all_tasks(opts) |> Enum.map(&serialize_task/1)
    json(conn, 200, %{tasks: tasks})
  end

  def handle_get(conn, id) do
    case Tasks.get_task(id) do
      {:ok, task} -> json(conn, 200, serialize_task(task))
      {:error, :not_found} -> json(conn, 404, %{error: "Task not found"})
    end
  end

  def handle_create(conn, params) do
    case Tasks.create_task(params) do
      {:ok, task} ->
        AIBrain.Task.Dispatcher.notify_pending(task.id)
        json(conn, 201, serialize_task(task))

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  def handle_update(conn, id, params) do
    case Tasks.get_task(id) do
      {:ok, task} ->
        case update_task(task, params) do
          {:ok, updated} ->
            if updated.status == "pending", do: notify_pending(updated.id)
            json(conn, 200, serialize_task(updated))

          {:error, changeset} ->
            validation_error(conn, changeset)
        end

      {:error, :not_found} ->
        json(conn, 404, %{error: "Task not found"})
    end
  end

  def handle_delete(conn, id) do
    case Tasks.get_task(id) do
      {:ok, task} ->
        cancel_linked_run(task)
        Tasks.delete_task(task)
        json(conn, 200, %{message: "Deleted"})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Task not found"})
    end
  end

  def handle_get_events(conn, id, _params) do
    events = AIBrain.Data.Events.list_by_task(id)
    json(conn, 200, %{events: events})
  end

  defp update_task(task, params) do
    {output, attrs} = Map.pop(params, "output")

    attrs =
      attrs
      |> Map.take(~w(title description status priority metadata depends_on parent_id))
      |> normalize_atom_keys()

    with {:ok, updated} <- Tasks.update_task(task, attrs) do
      if is_binary(output) do
        Tasks.update_task_result(updated, updated.status, output)
      else
        {:ok, updated}
      end
    end
  end

  defp normalize_atom_keys(params) do
    Map.new(params, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      pair -> pair
    end)
  end

  defp cancel_linked_run(%{run_id: run_id}) when is_binary(run_id) and run_id != "" do
    _ = AIBrain.Engine.Overseer.cancel_tx(AIBrain.Engine.Overseer, run_id)
    RunLifecycle.cancel(run_id, %{source: "api.goal_tasks"})
  rescue
    e ->
      Logger.debug(
        "GoalTasksHandler: failed to cancel linked run #{run_id}: #{Exception.message(e)}"
      )
  catch
    :exit, _ -> :ok
  end

  defp cancel_linked_run(_task), do: :ok

  defp notify_pending(task_id) do
    if Process.whereis(AIBrain.Task.Dispatcher) do
      AIBrain.Task.Dispatcher.notify_pending(task_id)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp validation_error(conn, %Ecto.Changeset{} = changeset) do
    json(conn, 422, %{
      error: "Validation failed",
      code: "validation_failed",
      errors: readable_errors(changeset)
    })
  end

  defp readable_errors(changeset) do
    traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp serialize_task(task) do
    metadata = task.metadata || %{}

    %{
      id: task.id,
      parent_id: task.parent_id,
      goal_id: task.goal_id,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      required_skills: task.required_skills || [],
      metadata: metadata,
      depends_on: task.depends_on || [],
      output: task.output,
      run_id: task.run_id,
      workspace_path: metadata["workspace_path"],
      autonomy_level: metadata["autonomy_level"],
      schedule_id: metadata["schedule_id"],
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
