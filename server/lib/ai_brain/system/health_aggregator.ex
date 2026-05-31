defmodule AIBrain.System.HealthAggregator do
  @moduledoc """
  Unified health view combining plan health, telemetry metrics, and system status.

  Provides a single endpoint for operators to assess overall system health.
  """

  alias AIBrain.Telemetry.Reporter

  @type system_status :: :healthy | :degraded | :unhealthy

  @doc """
  Return a comprehensive health snapshot.

  Fields:
    - system_status — overall status derived from all checks
    - uptime_seconds — process uptime
    - telemetry — aggregate metrics from the last hour
    - recent_alerts — last 20 bus alerts
    - db_status — database connectivity
  """
  def snapshot do
    telemetry = safe_fetch_metrics()
    alerts = safe_fetch_alerts()
    uptime = get_uptime()
    db_status = check_db()
    workload = safe_fetch_workload()

    %{
      system_status: derive_status(telemetry, db_status),
      uptime_seconds: uptime,
      checked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      telemetry: telemetry,
      recent_alerts: alerts,
      db: db_status,
      workload: workload
    }
  end

  @doc """
  Derive an overall system status from health signals.
  """
  def derive_status(telemetry, db_status) do
    conditions = [
      db_status == :ok,
      not error_rate_high?(telemetry)
    ]

    cond do
      Enum.all?(conditions) -> :healthy
      hd(conditions) == false -> :unhealthy
      true -> :degraded
    end
  end

  # ── Private ───────────────────────────────────────────────────────

  defp safe_fetch_metrics do
    Reporter.aggregate_metrics()
  rescue
    _ -> %{error: "unavailable"}
  end

  defp safe_fetch_alerts do
    alerts = AIBrain.Channel.Bus.recent(20)

    Enum.map(alerts, fn
      %AIBrain.Channel.Alert{} = a ->
        %{severity: a.severity, source: a.source, type: a.type, message: a.message}

      %{type: type} = m ->
        %{severity: :info, source: "legacy", type: type, message: Map.get(m, :message, "")}

      _ ->
        %{severity: :info, source: "unknown", message: "unknown alert format"}
    end)
  rescue
    _ -> []
  end

  defp get_uptime do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(AIBrain.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp error_rate_high?(%{llm_errors: errors, llm_calls: calls}) when calls > 0 do
    errors / calls > 0.5
  end

  defp error_rate_high?(_), do: false

  defp safe_fetch_workload do
    task_counts = fetch_task_counts()
    run_counts = fetch_run_counts()
    approval_count = fetch_pending_approvals()
    active_executors = fetch_active_executors()

    %{
      tasks: task_counts,
      runs: run_counts,
      pending_approvals: approval_count,
      active_executors: active_executors
    }
  rescue
    _ -> %{error: "unavailable"}
  end

  defp fetch_task_counts do
    import Ecto.Query
    alias AIBrain.Data.Task

    AIBrain.Repo.all(
      from(t in Task,
        group_by: t.status,
        select: {t.status, count(t.id)}
      )
    )
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp fetch_run_counts do
    import Ecto.Query
    alias AIBrain.Data.Run

    AIBrain.Repo.all(
      from(r in Run,
        where: r.inserted_at > ago(24, "hour"),
        group_by: r.status,
        select: {r.status, count(r.id)}
      )
    )
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp fetch_pending_approvals do
    import Ecto.Query
    alias AIBrain.Data.Run

    AIBrain.Repo.one(
      from(r in Run,
        where: r.status in ["waiting_approval", "waiting_assistant"],
        select: count(r.id)
      )
    ) || 0
  rescue
    _ -> 0
  end

  defp fetch_active_executors do
    AIBrain.Engine.Overseer.count_active()
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end
end
