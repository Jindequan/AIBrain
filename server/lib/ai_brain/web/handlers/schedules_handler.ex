defmodule AIBrain.Web.Handlers.SchedulesHandler do
  import Plug.Conn
  alias AIBrain.Data.{Runs, Schedules}
  alias AIBrain.Task.AutomationEngine

  def handle_list(conn, params) do
    opts =
      []
      |> maybe_put_opt(:status, params["status"])
      |> maybe_put_opt(:trigger_type, params["trigger_type"])

    rules = Schedules.list_schedules(opts)
    json(conn, 200, %{automation_rules: rules})
  end

  def handle_scan(conn, server \\ AutomationEngine) do
    case AutomationEngine.scan_now(server) do
      {:ok, fired_ids} ->
        json(conn, 200, %{
          ok: true,
          fired_schedule_ids: fired_ids,
          diagnostics: Schedules.diagnostics()
        })

      {:error, reason} ->
        json(conn, 500, %{ok: false, error: inspect(reason)})
    end
  end

  def handle_get(conn, id) do
    case Schedules.get_schedule(id) do
      {:ok, rule} -> json(conn, 200, rule)
      {:error, :not_found} -> json(conn, 404, %{error: "AutomationRule not found"})
    end
  end

  def handle_runs(conn, id, params) do
    limit = parse_int(params["limit"]) || 50

    case Schedules.get_schedule(id) do
      {:ok, _rule} ->
        runs =
          Runs.list_runs_for_ref("schedule", id, limit: limit)
          |> Enum.map(&serialize_run/1)

        json(conn, 200, %{schedule_id: id, runs: runs})

      {:error, :not_found} ->
        json(conn, 404, %{error: "AutomationRule not found"})
    end
  end

  def handle_create(conn, params) do
    params = translate_params(params)

    case Schedules.create_schedule(params) do
      {:ok, rule} -> json(conn, 201, rule)
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_update(conn, id, params) do
    params = translate_params(params)

    case Schedules.update_schedule(id, params) do
      {:ok, updated} -> json(conn, 200, updated)
      {:error, :not_found} -> json(conn, 404, %{error: "AutomationRule not found"})
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_delete(conn, id) do
    case Schedules.delete_schedule(id) do
      :ok -> json(conn, 200, %{message: "Deleted"})
      {:error, :not_found} -> json(conn, 404, %{error: "AutomationRule not found"})
    end
  end

  defp translate_params(params) do
    case params["action"] do
      nil ->
        params

      action ->
        params
        |> Map.merge(%{
          "action_type" => action["type"] || "create_task",
          "action_config" => %{
            "title" => action["title"],
            "prompt" => action["prompt"],
            "message" => action["message"],
            "description" => action["message"],
            "required_skills" => action["required_skills"] || [],
            "goal_id" => action["goal_id"],
            "workspace_path" => action["workspace_path"],
            "autonomy_level" => action["autonomy_level"],
            "max_turns" => action["max_turns"],
            "max_wall_time" => action["max_wall_time"],
            "notify_channels" => action["notify_channels"] || []
          }
        })
        |> Map.drop(["action"])
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp serialize_run(run) do
    %{
      id: run.id,
      source_type: run.source_type,
      source_id: run.source_id,
      status: run.status,
      phase: run.phase,
      mode: run.mode,
      title: run.title,
      objective: run.objective,
      output_summary: run.output_summary,
      error: run.error,
      inserted_at: run.inserted_at,
      updated_at: run.updated_at,
      completed_at: run.completed_at
    }
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end
end
