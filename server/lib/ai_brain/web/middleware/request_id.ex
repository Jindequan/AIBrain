defmodule AIBrain.Web.Middleware.RequestId do
  @moduledoc """
  Injects a trace_id into Logger metadata for each HTTP request.

  Reads from X-Request-Id header or generates a new one.
  The trace_id flows through all log calls within the request lifecycle.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    trace_id =
      case get_req_header(conn, "x-request-id") do
        [id | _] when byte_size(id) > 0 -> id
        _ -> generate_trace_id()
      end

    Logger.metadata(trace_id: trace_id)

    conn
    |> put_resp_header("x-trace-id", trace_id)
    |> put_private(:trace_id, trace_id)
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
