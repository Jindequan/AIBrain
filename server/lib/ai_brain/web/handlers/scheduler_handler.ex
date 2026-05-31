defmodule AIBrain.Web.Handlers.SchedulerHandler do
  import Plug.Conn
  require Logger
  alias AIBrain.Data.Schedules
  alias AIBrain.Task.AutomationEngine

  def handle_list(conn) do
    items = Schedules.list_schedules() |> Enum.map(&serialize_item/1)
    json_response(conn, 200, %{items: items, diagnostics: Schedules.diagnostics()})
  end

  def handle_scan(conn, server \\ AutomationEngine) do
    case AutomationEngine.scan_now(server) do
      {:ok, fired_ids} ->
        json_response(conn, 200, %{
          ok: true,
          fired_schedule_ids: fired_ids,
          diagnostics: Schedules.diagnostics()
        })

      {:error, reason} ->
        json_response(conn, 500, %{ok: false, error: inspect(reason)})
    end
  end

  def handle_cancel(conn, item_id) do
    case Schedules.update_schedule(item_id, %{"status" => "cancelled"}) do
      {:ok, _schedule} ->
        json_response(conn, 200, %{ok: true})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "not found"})

      {:error, reason} ->
        Logger.error("Failed to cancel scheduler item: #{inspect(reason)}")
        json_response(conn, 500, %{error: "Failed to cancel scheduler item"})
    end
  end

  defp serialize_item(schedule) do
    trigger_config = schedule.trigger_config || %{}
    action_config = schedule.action_config || %{}

    %{
      id: schedule.id,
      type: schedule.trigger_type,
      trigger_at: format_dt(schedule.next_fire_at),
      cron_expression: trigger_config["cron"],
      next_fire_at: format_dt(schedule.next_fire_at),
      action: action_config["title"] || action_config["description"] || schedule.action_type,
      status: schedule.status,
      created_at: format_dt(schedule.inserted_at),
      metadata: %{
        action_type: schedule.action_type,
        action_config: action_config,
        trigger_config: trigger_config,
        last_fired_at: format_dt(schedule.last_fired_at),
        last_result: schedule.last_result,
        goal_id: action_config["goal_id"],
        workspace_path: action_config["workspace_path"],
        autonomy_level: action_config["autonomy_level"]
      }
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_dt(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
