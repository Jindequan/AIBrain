defmodule AIBrain.Web.Handlers.DashboardHandler do
  @moduledoc """
  Serves a lightweight HTML dashboard at /dashboard showing system health,
  telemetry metrics, and recent alerts.
  """

  import Plug.Conn

  def handle_dashboard(conn) do
    snap = AIBrain.System.HealthAggregator.snapshot()

    conn
    |> put_resp_content_type("text/html; charset=utf-8")
    |> send_resp(200, render(snap))
  end

  defp render(snap) do
    status_color =
      case snap.system_status do
        :healthy -> "#22c55e"
        :degraded -> "#f59e0b"
        :unhealthy -> "#ef4444"
      end

    status_text = snap.system_status |> to_string() |> String.upcase()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AIBrain Dashboard</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; }
      h1 { font-size: 1.5rem; margin-bottom: 8px; }
      .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin-top: 16px; }
      .card { background: #1e293b; border-radius: 8px; padding: 16px; border: 1px solid #334155; }
      .card h2 { font-size: 0.875rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 12px; }
      .metric { display: flex; justify-content: space-between; padding: 4px 0; font-size: 0.875rem; }
      .metric .value { font-weight: 600; color: #f1f5f9; }
      .status-badge { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 0.75rem; font-weight: 700; }
      .alert-item { font-size: 0.8rem; padding: 6px 0; border-bottom: 1px solid #334155; }
      .alert-item:last-child { border-bottom: none; }
      .sev-critical { color: #ef4444; }
      .sev-warning { color: #f59e0b; }
      .sev-info { color: #3b82f6; }
      .bar { height: 4px; border-radius: 2px; margin-top: 8px; }
    </style>
    </head>
    <body>
    <h1>AIBrain Dashboard</h1>
    <span class="status-badge" style="background: #{status_color}20; color: #{status_color}; border: 1px solid #{status_color}40">#{status_text}</span>
    <span style="margin-left: 12px; font-size: 0.8rem; color: #64748b;">uptime: #{format_uptime(snap.uptime_seconds)} | checked: #{snap.checked_at}</span>

    <div class="grid">
      <div class="card">
        <h2>LLM</h2>
        <div class="metric"><span>Calls (1h)</span><span class="value">#{get_in(snap.telemetry, [:llm_calls]) || 0}</span></div>
        <div class="metric"><span>Errors</span><span class="value">#{get_in(snap.telemetry, [:llm_errors]) || 0}</span></div>
        <div class="metric"><span>Avg Latency</span><span class="value">#{get_in(snap.telemetry, [:avg_llm_latency_ms]) || 0}ms</span></div>
        <div class="metric"><span>P95 Latency</span><span class="value">#{get_in(snap.telemetry, [:p95_llm_latency_ms]) || 0}ms</span></div>
      </div>
      <div class="card">
        <h2>Tools</h2>
        <div class="metric"><span>Calls (1h)</span><span class="value">#{get_in(snap.telemetry, [:tool_calls]) || 0}</span></div>
        <div class="metric"><span>Errors</span><span class="value">#{get_in(snap.telemetry, [:tool_errors]) || 0}</span></div>
        <div class="metric"><span>Avg Latency</span><span class="value">#{get_in(snap.telemetry, [:avg_tool_latency_ms]) || 0}ms</span></div>
      </div>
      <div class="card">
        <h2>Queries</h2>
        <div class="metric"><span>Total (1h)</span><span class="value">#{get_in(snap.telemetry, [:queries]) || 0}</span></div>
        <div class="metric"><span>Failures</span><span class="value">#{get_in(snap.telemetry, [:query_failures]) || 0}</span></div>
        <div class="metric"><span>Avg Duration</span><span class="value">#{get_in(snap.telemetry, [:avg_query_duration_ms]) || 0}ms</span></div>
        <div class="metric"><span>Router Selects</span><span class="value">#{get_in(snap.telemetry, [:router_selections]) || 0}</span></div>
      </div>
      <div class="card">
        <h2>System</h2>
        <div class="metric"><span>Database</span><span class="value">#{snap.db}</span></div>
        <div class="metric"><span>Uptime</span><span class="value">#{format_uptime(snap.uptime_seconds)}</span></div>
      </div>
      <div class="card">
        <h2>Workload</h2>
        <div class="metric"><span>Active Executors</span><span class="value">#{get_in(snap, [:workload, :active_executors]) || 0}</span></div>
        <div class="metric"><span>Pending Approvals</span><span class="value">#{get_in(snap, [:workload, :pending_approvals]) || 0}</span></div>
        <div class="metric"><span>Tasks Pending</span><span class="value">#{get_in(snap, [:workload, :tasks, "pending"]) || 0}</span></div>
        <div class="metric"><span>Tasks Running</span><span class="value">#{get_in(snap, [:workload, :tasks, "running"]) || 0}</span></div>
        <div class="metric"><span>Runs Active (24h)</span><span class="value">#{get_in(snap, [:workload, :runs, "running"]) || 0}</span></div>
        <div class="metric"><span>Runs Waiting Approval</span><span class="value">#{get_in(snap, [:workload, :runs, "waiting_approval"]) || 0}</span></div>
      </div>
    </div>

    <div class="card" style="margin-top: 16px;">
      <h2>Recent Alerts</h2>
      #{render_alerts(snap.recent_alerts)}
    </div>
    </body>
    </html>
    """
  end

  defp render_alerts([]), do: "<div style='font-size:0.8rem;color:#64748b'>No recent alerts</div>"

  defp render_alerts(alerts) do
    alerts
    |> Enum.map(fn alert ->
      sev_class = "sev-#{alert.severity}"

      # Escape user-controlled data to prevent XSS
      safe_source = html_escape(alert.source)
      safe_type = html_escape(alert.type)
      safe_message = html_escape(alert.message)

      """
      <div class="alert-item">
        <span class="#{sev_class}">[#{alert.severity |> to_string() |> String.upcase()}]</span>
        <span style="color:#64748b">#{safe_source}:#{safe_type}</span>
        <span>#{safe_message}</span>
      </div>
      """
    end)
    |> Enum.join("\n")
  end

  defp html_escape(nil), do: ""

  defp html_escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp html_escape(value), do: to_string(value)

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)
    secs = rem(seconds, 60)
    "#{hours}h #{minutes}m #{secs}s"
  end
end
