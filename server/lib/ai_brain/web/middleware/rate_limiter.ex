defmodule AIBrain.Web.Middleware.RateLimiter do
  @moduledoc """
  Simple per-IP rate limiter using ETS.

  Limits each source IP to `max_requests` requests within `window_ms` milliseconds.
  """

  @table :rate_limiter
  @default_max_requests 30
  @default_window_ms 60_000

  def init(opts) do
    max_requests = Keyword.get(opts, :max_requests, @default_max_requests)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)
    {max_requests, window_ms}
  end

  def call(conn, {max_requests, window_ms}) do
    ensure_table()
    ip = client_ip(conn)
    key = {ip, conn.request_path}
    now = System.monotonic_time(:millisecond)

    # Clean old entries for this key
    :ets.select_delete(@table, [
      {{{:_, :_}, :_, :_}, [{:<, {:element, 3, {:element, 2, "$1"}}, now - window_ms}], [true]}
    ])

    # Count recent requests
    count =
      case :ets.lookup(@table, key) do
        [{^key, timestamps}] ->
          valid = Enum.filter(timestamps, fn t -> t > now - window_ms end)
          length(valid)

        [] ->
          0
      end

    if count >= max_requests do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        429,
        Jason.encode!(%{error: "Rate limit exceeded. Please try again later."})
      )
      |> Plug.Conn.halt()
    else
      # Record this request
      case :ets.lookup(@table, key) do
        [{^key, timestamps}] ->
          valid = Enum.filter(timestamps, fn t -> t > now - window_ms end)
          :ets.insert(@table, {key, [now | valid]})

        [] ->
          :ets.insert(@table, {key, [now]})
      end

      conn
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> :ok
    end
  end

  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> hd() |> String.trim()

      _ ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end
