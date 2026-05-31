defmodule AIBrain.Web.Server do
  @moduledoc """
  HTTP 服务器和 WebSocket 网关。

  路由已拆分到 Web.Routes.APIv1，这里只处理：
  - 请求日志
  - WebSocket 升级
  - 转发到 API v1 路由
  """

  use Plug.Router

  @websocket_timeout_ms Application.compile_env(:ai_brain, :websocket_timeout_ms, 60_000)

  plug(:request_id)
  plug(Plug.Logger)
  plug(Plug.Head)

  # Serve frontend static assets in production.
  # Dev: Vite handles these. Prod: bin/build copies frontend/dist → priv/static.
  if Application.compile_env(:ai_brain, :static_dir, nil) do
    plug(Plug.Static,
      at: "/",
      from: Application.compile_env(:ai_brain, :static_dir),
      gzip: true,
      only: ~w(assets logo favicon index.html)
    )
  end

  plug(:match)
  plug(:dispatch)

  # WebSocket 升级
  get "/api/v1/ws" do
    if origin_allowed?(conn) do
      conn
      |> WebSockAdapter.upgrade(AIBrain.Web.Socket, [], timeout: @websocket_timeout_ms)
      |> halt()
    else
      conn
      |> Plug.Conn.send_resp(403, Jason.encode!(%{error: "Origin not allowed"}))
      |> halt()
    end
  end

  # 转发所有其他请求到 API v1 路由
  forward("/", to: AIBrain.Web.Routes.APIv1)

  defp request_id(conn, opts) do
    AIBrain.Web.Middleware.RequestId.call(conn, opts)
  end

  @default_ws_origins [
    "http://localhost:3000",
    "http://localhost:4100",
    "http://localhost:5173",
    "http://localhost:5200",
    "http://localhost:5201",
    "http://localhost:43225",
    "http://localhost:74325",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:4100",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5200",
    "http://127.0.0.1:5201",
    "http://127.0.0.1:43225",
    "http://127.0.0.1:74325"
  ]

  # Allow WebSocket connections from configured CORS origins or same-origin (no Origin header)
  defp origin_allowed?(conn) do
    case Plug.Conn.get_req_header(conn, "origin") do
      # Non-browser clients don't send Origin
      [] ->
        true

      [origin] ->
        allowed = Application.get_env(:ai_brain, :cors_origins, @default_ws_origins)
        origin in allowed
    end
  end
end
