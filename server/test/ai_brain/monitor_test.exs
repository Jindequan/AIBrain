defmodule AIBrain.MonitorTest do
  use AIBrain.DataCase

  alias AIBrain.Data.Schedules
  alias AIBrain.Monitor

  test "create stores monitor as a unified schedule" do
    assert {:ok, id} = Monitor.create("Inbox watch", "Check urgent mail", "*/5 * * * *")

    assert {:ok, schedule} = Schedules.get_schedule(id)
    assert schedule.name == "Inbox watch"
    assert schedule.trigger_type == "cron"
    assert schedule.trigger_config["cron"] == "*/5 * * * *"
    assert schedule.action_type == "run_query"
    assert schedule.action_config["kind"] == "monitor"
    assert schedule.action_config["prompt"] == "Check urgent mail"
    assert schedule.next_fire_at
  end

  test "list returns only monitor schedules in legacy monitor shape" do
    {:ok, monitor_id} = Monitor.create("Health watch", "Check health data", "*/10 * * * *")

    {:ok, _non_monitor} =
      Schedules.create_schedule(%{
        name: "Daily brief",
        trigger_type: "cron",
        trigger_config: %{"cron" => "0 9 * * *"},
        action_type: "run_query",
        action_config: %{"prompt" => "Daily brief"},
        status: "active"
      })

    monitors = Monitor.list()

    assert [%{id: ^monitor_id, type: "monitor", action: "Check health data"}] = monitors
  end

  test "delete removes monitor schedules only" do
    {:ok, monitor_id} = Monitor.create("Price watch", "Check price", "*/15 * * * *")

    {:ok, non_monitor} =
      Schedules.create_schedule(%{
        name: "Daily brief",
        trigger_type: "cron",
        trigger_config: %{"cron" => "0 9 * * *"},
        action_type: "run_query",
        action_config: %{"prompt" => "Daily brief"},
        status: "active"
      })

    assert :ok = Monitor.delete(monitor_id)
    assert {:error, :not_found} = Schedules.get_schedule(monitor_id)

    assert {:error, :not_found} = Monitor.delete(non_monitor.id)
    assert {:ok, _schedule} = Schedules.get_schedule(non_monitor.id)
  end
end
