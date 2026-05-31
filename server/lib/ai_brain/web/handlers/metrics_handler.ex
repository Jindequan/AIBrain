defmodule AIBrain.Web.Handlers.MetricsHandler do
  @moduledoc """
  HTTP handler for telemetry metrics at /api/v1/metrics.

  Returns aggregate metrics for the dashboard health panel.
  """

  def handle_get(conn) do
    metrics = AIBrain.Telemetry.Reporter.aggregate_metrics()

    body =
      Jason.encode!(%{
        status: :ok,
        data: metrics,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    Plug.Conn.send_resp(conn, 200, body)
  end

  def handle_get_spans(conn) do
    params = Plug.Conn.fetch_query_params(conn).query_params

    limit = parse_int(params, "limit", 100)
    event = params["event"]
    min_duration = parse_float(params, "min_duration_ms")

    spans =
      AIBrain.Telemetry.Reporter.query_spans(
        limit: limit,
        event: event,
        min_duration_ms: min_duration
      )

    body =
      Jason.encode!(%{
        status: :ok,
        data: spans,
        count: length(spans)
      })

    Plug.Conn.send_resp(conn, 200, body)
  end

  defp parse_int(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      s when is_binary(s) -> String.to_integer(s)
    end
  rescue
    _ -> default
  end

  defp parse_float(params, key) do
    case Map.get(params, key) do
      nil -> nil
      s when is_binary(s) -> String.to_float(s)
    end
  rescue
    _ -> nil
  end
end
