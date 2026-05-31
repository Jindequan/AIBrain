defmodule AIBrain.Web.Handlers.HealthHandler do
  @moduledoc """
  Health check endpoint. Returns system status with aggregated health data.
  """

  import Plug.Conn

  def handle_health(conn) do
    snap = AIBrain.System.HealthAggregator.snapshot()

    response = %{
      status: snap.system_status |> to_string(),
      service: "AIBrain",
      version: "0.1.0",
      timestamp: snap.checked_at,
      uptime: snap.uptime_seconds,
      db: snap.db |> to_string(),
      metrics: snap.telemetry
    }

    status_code =
      case snap.system_status do
        :healthy -> 200
        :degraded -> 200
        :unhealthy -> 503
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end
end
