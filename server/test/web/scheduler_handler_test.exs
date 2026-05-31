defmodule AIBrain.Web.SchedulerHandlerTest do
  use AIBrain.DataCase
  import Plug.Test

  alias AIBrain.Data.{RunContextRefs, Runs, Schedules}
  alias AIBrain.Task.AutomationEngine
  alias AIBrain.Web.Handlers.{SchedulesHandler, SchedulerHandler}

  test "list returns unified schedules in legacy scheduler item shape" do
    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "Daily brief",
        trigger_type: "cron",
        trigger_config: %{"cron" => "0 9 * * *"},
        action_type: "run_query",
        action_config: %{"title" => "Brief"},
        next_fire_at: ~U[2026-05-19 01:00:00Z]
      })

    conn = SchedulerHandler.handle_list(conn(:get, "/api/v1/scheduler"))

    assert conn.status == 200
    assert [%{"id" => id} = item] = Jason.decode!(conn.resp_body)["items"]
    assert id == schedule.id
    assert item["type"] == "cron"
    assert item["cron_expression"] == "0 9 * * *"
    assert item["action"] == "Brief"
    assert item["metadata"]["action_type"] == "run_query"
    assert body = Jason.decode!(conn.resp_body)
    assert body["diagnostics"]["counts"]["total"] == 1
  end

  test "cancel marks unified schedule cancelled" do
    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "One shot",
        trigger_type: "time",
        action_type: "run_query",
        next_fire_at: ~U[2026-05-19 01:00:00Z]
      })

    conn =
      SchedulerHandler.handle_cancel(
        conn(:delete, "/api/v1/scheduler/#{schedule.id}"),
        schedule.id
      )

    assert conn.status == 200
    assert {:ok, updated} = Schedules.get_schedule(schedule.id)
    assert updated.status == "cancelled"
  end

  test "scan endpoint fires due automation through supplied engine" do
    parent = self()

    runner = fn attrs, _opts ->
      send(parent, {:started, attrs.source_id})
      {:ok, "run-from-handler"}
    end

    server =
      start_supervised!(
        {AutomationEngine,
         name: :"automation_engine_#{System.unique_integer([:positive])}",
         scan_interval: 3600,
         runner: runner}
      )

    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "Scan me",
        trigger_type: "time",
        action_type: "run_query",
        action_config: %{"prompt" => "Do the scan"},
        next_fire_at: DateTime.utc_now() |> DateTime.add(-60, :second)
      })

    conn = SchedulerHandler.handle_scan(conn(:post, "/api/v1/scheduler/scan"), server)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["fired_schedule_ids"] == [schedule.id]
    schedule_id = schedule.id
    assert_receive {:started, ^schedule_id}
  end

  test "automation rule create preserves runnable action prompt" do
    conn =
      SchedulesHandler.handle_create(
        conn(:post, "/api/v1/automation_rules"),
        %{
          "name" => "Market brief",
          "trigger_type" => "cron",
          "trigger_config" => %{"cron" => "0 9 * * *"},
          "status" => "active",
          "action" => %{
            "type" => "run_query",
            "title" => "Daily market brief",
            "prompt" => "每天给我美股消息",
            "workspace_path" => "/tmp/aibrain",
            "autonomy_level" => 1
          }
        }
      )

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["action_type"] == "run_query"
    assert body["action_config"]["title"] == "Daily market brief"
    assert body["action_config"]["prompt"] == "每天给我美股消息"
    assert body["action_config"]["workspace_path"] == "/tmp/aibrain"
    assert body["action_config"]["autonomy_level"] == 1
  end

  test "automation rule run history returns runs linked by schedule ref" do
    {:ok, schedule} =
      Schedules.create_schedule(%{
        name: "History",
        trigger_type: "time",
        action_type: "run_query",
        next_fire_at: ~U[2026-05-19 01:00:00Z]
      })

    {:ok, run} =
      Runs.create_run(%{
        source_type: "schedule",
        source_id: schedule.id,
        status: "completed",
        phase: "completed",
        mode: "scheduled",
        title: "History run"
      })

    :ok =
      RunContextRefs.create_many(run.id, [
        %{ref_type: "schedule", ref_id: schedule.id, role: "trigger"}
      ])

    conn =
      SchedulesHandler.handle_runs(
        conn(:get, "/api/v1/automation_rules/#{schedule.id}/runs"),
        schedule.id,
        %{}
      )

    assert conn.status == 200
    assert [%{"id" => run_id, "mode" => "scheduled"}] = Jason.decode!(conn.resp_body)["runs"]
    assert run_id == run.id
  end
end
