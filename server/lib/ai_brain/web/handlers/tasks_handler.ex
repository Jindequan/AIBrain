defmodule AIBrain.Web.Handlers.TasksHandler do
  import Plug.Conn
  require Logger
  alias AIBrain.AgentRuntime.{FileStore, RunLifecycle}
  alias AIBrain.Data.Tasks

  def handle_list(conn) do
    tasks = Tasks.list_all_tasks() |> Enum.map(&serialize_task/1)
    json_response(conn, 200, %{tasks: tasks})
  end

  def handle_stop(conn, task_id) do
    with {:ok, task} <- Tasks.get_task(task_id),
         {:ok, updated} <- Tasks.update_task(task, %{status: "cancelled"}) do
      if task.run_id do
        _ = AIBrain.Engine.Overseer.cancel_tx(AIBrain.Engine.Overseer, task.run_id)
        RunLifecycle.cancel(task.run_id, %{source: "api.tasks"})
      end

      json_response(conn, 200, %{ok: true, task: serialize_task(updated)})
    else
      {:error, :not_found} ->
        json_response(conn, 404, %{error: "not found"})

      {:error, reason} ->
        Logger.error("Failed to stop task #{task_id}: #{inspect(reason)}")
        json_response(conn, 500, %{error: "Failed to stop task"})
    end
  end

  def handle_output(conn, task_id) do
    with {:ok, task} <- Tasks.get_task(task_id),
         {:ok, output} <- task_output(task) do
      json_response(conn, 200, %{task_id: task_id, output: output})
    else
      {:error, :not_found} ->
        json_response(conn, 404, %{error: "not found"})

      {:error, reason} ->
        Logger.error("Failed to get output for task #{task_id}: #{inspect(reason)}")
        json_response(conn, 500, %{error: "Failed to get task output"})
    end
  end

  defp serialize_task(task) do
    %{
      id: task.id,
      goal_id: task.goal_id,
      title: task.title,
      status: task.status,
      description: task.description,
      run_id: task.run_id,
      output: task.output,
      created_at: format_dt(task.inserted_at),
      updated_at: format_dt(task.updated_at),
      metadata: task.metadata
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_dt(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp task_output(%{metadata: %{"output_path" => path}}) when is_binary(path) and path != "" do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_output(%{run_id: run_id, output: output}) when is_binary(run_id) and run_id != "" do
    case FileStore.read_output(run_id) do
      {:ok, text} -> {:ok, text}
      {:error, :not_found} when is_binary(output) -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp task_output(%{output: output}) when is_binary(output), do: {:ok, output}
  defp task_output(_task), do: {:error, :not_found}

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
