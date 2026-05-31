defmodule AIBrain.Web.Routes.APIv1 do
  @moduledoc """
  API v1 routes extracted from Web.Server.

  All /api/v1/* routes are defined here.
  """

  use Plug.Router

  import Plug.Conn

  alias AIBrain.Web.Handlers.{
    ArtifactHandler,
    AssistantsHandler,
    ActiveRunsHandler,
    ChannelConfigHandler,
    ChannelsHandler,
    ContextLinkHandler,
    DashboardHandler,
    DiscordWebhookHandler,
    DocsHandler,
    FeishuWebhookHandler,
    WechatWebhookHandler,
    WhatsappWebhookHandler,
    EventHandler,
    FsHandler,
    GoalTasksHandler,
    GoalsHandler,
    HealthHandler,
    InteractionHandler,
    MemoryHandler,
    MetricsHandler,
    PlanningHandler,
    ProvidersHandler,
    QueryHandler,
    RunsHandler,
    SchedulerHandler,
    SchedulesHandler,
    SearchHandler,
    SessionHandler,
    SessionsHandler,
    TasksHandler,
    ToolsHandler,
    UserHandler,
    UserPromptsHandler,
    WebhookHandler,
    WorkspacesHandler
  }

  plug(:put_cors_headers)
  plug(:rate_limit_query)

  plug(Plug.Parsers,
    parsers: [:json, :multipart],
    pass: ["application/json"],
    json_decoder: Jason,
    length: Application.compile_env(:ai_brain, :http_max_body_bytes, 10_000_000)
  )

  plug(:match)
  plug(:dispatch)

  @default_origins [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173"
  ]

  defp put_cors_headers(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()
    allowed_origins = Application.get_env(:ai_brain, :cors_origins, @default_origins)

    conn =
      if origin && origin in allowed_origins do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
      else
        conn
      end
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "content-type, authorization")

    conn
  end

  # Rate limiter — only applies to expensive query endpoints
  defp rate_limit_query(conn, _opts) do
    if conn.request_path in ["/api/v1/query", "/api/v1/query/stream"] do
      AIBrain.Web.Middleware.RateLimiter.call(
        conn,
        {
          Application.get_env(:ai_brain, :query_rate_limit_max_requests, 30),
          Application.get_env(:ai_brain, :query_rate_limit_window_ms, 60_000)
        }
      )
    else
      conn
    end
  end

  # CORS preflight
  options _ do
    send_resp(conn, 204, "")
  end

  # Full health check with system metrics
  get "/health" do
    HealthHandler.handle_health(conn)
  end

  # Lightweight health check for Electron / monitoring
  # Returns simple {"status":"ok"} — always succeeds
  get "/api/v1/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok"}))
  end

  # ── User Settings ──────────────────────────────
  get "/api/v1/settings" do
    settings = AIBrain.Settings.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(settings))
  end

  put "/api/v1/settings" do
    AIBrain.Settings.merge(conn.body_params)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(AIBrain.Settings.all()))
  end

  # ── User Management ─────────────────────────────
  get "/api/v1/users" do
    UserHandler.handle_list(conn)
  end

  post "/api/v1/users" do
    UserHandler.handle_create(conn, conn.body_params)
  end

  get "/api/v1/users/:id" do
    UserHandler.handle_get_by_id(conn, id)
  end

  put "/api/v1/users/:id" do
    UserHandler.handle_update(conn, Map.put(conn.body_params, "id", id))
  end

  delete "/api/v1/users/:id" do
    UserHandler.handle_delete(conn, id)
  end

  # Legacy routes (backward compatibility)
  get "/api/v1/user" do
    UserHandler.handle_get(conn)
  end

  put "/api/v1/user" do
    UserHandler.handle_update(conn, conn.body_params)
  end

  get "/dashboard" do
    DashboardHandler.handle_dashboard(conn)
  end

  # 全局搜索
  get "/api/v1/search" do
    SearchHandler.handle_global_search(conn)
  end

  # API 文档
  get "/api/docs" do
    DocsHandler.handle_docs(conn)
  end

  # 查询接口
  post "/api/v1/query" do
    QueryHandler.handle_query(conn, conn.body_params)
  end

  # 流式查询接口 (SSE)
  post "/api/v1/query/stream" do
    QueryHandler.handle_stream_query(conn, conn.body_params)
  end

  # Sessions list (must be before /:id)
  get "/api/v1/sessions" do
    SessionsHandler.handle_list(conn)
  end

  # Workspaces
  get "/api/v1/workspaces" do
    WorkspacesHandler.handle_list(conn)
  end

  get "/api/v1/workspaces/:id" do
    WorkspacesHandler.handle_get(conn, id)
  end

  # Unified runs
  get "/api/v1/runs" do
    RunsHandler.handle_list(conn, conn.params)
  end

  # Static sub-routes must precede /:id
  get "/api/v1/runs/active" do
    ActiveRunsHandler.handle_active(conn)
  end

  get "/api/v1/runs/stats" do
    RunsHandler.handle_stats(conn, conn.params)
  end

  post "/api/v1/runs" do
    RunsHandler.handle_create(conn, conn.body_params)
  end

  post "/api/v1/runs/:id/cancel" do
    RunsHandler.handle_cancel(conn, id)
  end

  get "/api/v1/runs/:id/steps" do
    RunsHandler.handle_steps(conn, id, conn.params)
  end

  get "/api/v1/runs/:id/evidence" do
    RunsHandler.handle_evidence(conn, id)
  end

  get "/api/v1/runs/:id/verification" do
    RunsHandler.handle_verification(conn, id)
  end

  get "/api/v1/runs/:id/output" do
    RunsHandler.handle_output(conn, id)
  end

  get "/api/v1/runs/:id/messages" do
    RunsHandler.handle_messages(conn, id)
  end

  get "/api/v1/runs/:id/events" do
    RunsHandler.handle_events(conn, id, conn.params)
  end

  get "/api/v1/runs/:id" do
    RunsHandler.handle_get(conn, id)
  end

  post "/api/v1/tasks/:id/stop" do
    TasksHandler.handle_stop(conn, id)
  end

  get "/api/v1/tasks/:id/output" do
    TasksHandler.handle_output(conn, id)
  end

  # Session 管理
  get "/api/v1/sessions/:id" do
    SessionHandler.handle_get_session(conn, id)
  end

  get "/api/v1/sessions/:id/messages" do
    SessionHandler.handle_get_messages(conn, id)
  end

  post "/api/v1/sessions" do
    SessionHandler.handle_create_session(conn, conn.body_params)
  end

  put "/api/v1/sessions/:id" do
    SessionHandler.handle_update_session(conn, id, conn.body_params)
  end

  delete "/api/v1/sessions/:id" do
    SessionHandler.handle_delete_session(conn, id)
  end

  delete "/api/v1/sessions/:id/messages/:message_id" do
    SessionHandler.handle_delete_message(conn, id, message_id)
  end

  post "/api/v1/sessions/:id/messages/truncate" do
    SessionHandler.handle_truncate_messages(conn, id, conn.body_params)
  end

  post "/api/v1/sessions/:id/resume" do
    SessionHandler.handle_resume_session(conn, id, conn.body_params)
  end

  post "/api/v1/sessions/:id/stop" do
    SessionHandler.handle_stop_session(conn, id)
  end

  get "/api/v1/sessions/:id/events" do
    EventHandler.handle_get_events(conn, id)
  end

  get "/api/v1/sessions/:id/search" do
    SessionHandler.handle_search(conn, id)
  end

  post "/api/v1/sessions/:id/messages" do
    SessionHandler.handle_send_message(conn, id, conn.body_params)
  end

  # Interactions
  get "/api/v1/interactions" do
    InteractionHandler.handle_list(conn, conn.params)
  end

  get "/api/v1/interactions/:id" do
    InteractionHandler.handle_get(conn, id)
  end

  post "/api/v1/interactions/:id/resolve" do
    InteractionHandler.handle_resolve(conn, id, conn.body_params)
  end

  post "/api/v1/interactions/:id/stop_proxy" do
    InteractionHandler.handle_stop_proxy(conn, id, conn.body_params)
  end

  get "/api/v1/sessions/:id/interactions" do
    InteractionHandler.handle_session_chain(conn, id)
  end

  # Providers
  get "/api/v1/model-settings" do
    ProvidersHandler.handle_model_settings(conn)
  end

  post "/api/v1/settings/providers" do
    ProvidersHandler.handle_configure_provider(conn, conn.body_params)
  end

  post "/api/v1/settings/credentials" do
    ProvidersHandler.handle_store_credential(conn, conn.body_params)
  end

  delete "/api/v1/settings/providers/:name" do
    ProvidersHandler.handle_delete_provider_settings(conn, name)
  end

  post "/api/v1/settings/model-policy" do
    ProvidersHandler.handle_update_model_policy(conn, conn.body_params)
  end

  post "/api/v1/settings/catalog/refresh" do
    ProvidersHandler.handle_refresh_catalog(conn)
  end

  get "/api/v1/providers" do
    ProvidersHandler.handle_list(conn)
  end

  post "/api/v1/providers" do
    ProvidersHandler.handle_add(conn, conn.body_params)
  end

  # OpenRouter providers metadata. Keep these before /providers/:id so
  # "openrouter" is not interpreted as a provider id.
  get "/api/v1/providers/openrouter" do
    ProvidersHandler.handle_list_openrouter_providers(conn)
  end

  post "/api/v1/providers/openrouter/fetch" do
    ProvidersHandler.handle_fetch_openrouter_providers(conn)
  end

  put "/api/v1/providers/:id" do
    ProvidersHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/providers/:id" do
    ProvidersHandler.handle_delete(conn, id)
  end

  post "/api/v1/providers/:id/enable" do
    ProvidersHandler.handle_enable(conn, id)
  end

  post "/api/v1/providers/:id/disable" do
    ProvidersHandler.handle_disable(conn, id)
  end

  post "/api/v1/providers/:id/fetch_models" do
    ProvidersHandler.handle_fetch_models(conn, id)
  end

  get "/api/v1/providers/:id/models" do
    ProvidersHandler.handle_list_models(conn, id)
  end

  # Global model registry
  post "/api/v1/models/fetch" do
    ProvidersHandler.handle_fetch_all_models(conn)
  end

  get "/api/v1/models" do
    ProvidersHandler.handle_list_provider_models(conn, conn.params)
  end

  # Unified model listing (across all providers)
  get "/api/v1/models/all" do
    ProvidersHandler.handle_list_all_models(conn)
  end

  # ── System Settings ────────────────────────────
  get "/api/v1/system/default_models" do
    defaults = AIBrain.Data.SystemSetting.all_default_models()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(defaults))
  end

  put "/api/v1/system/default_model" do
    params = conn.body_params
    provider = params["provider"]
    model = params["model"]
    category = params["category"] || "normal"

    if is_binary(provider) and is_binary(model) do
      case AIBrain.Provider.Registry.get(provider) do
        {:ok, p} ->
          allowed? =
            model in AIBrain.Provider.Info.enabled_models(p) and
              AIBrain.Web.Handlers.ProvidersHandler.default_model_allowed?(category, p, model)

          if allowed? do
            case AIBrain.Data.SystemSetting.set_default_model(category, {provider, model}) do
              {:ok, _setting} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(
                  200,
                  Jason.encode!(%{ok: true, provider: provider, model: model, category: category})
                )

              {:error, :invalid_category} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(400, Jason.encode!(%{error: "invalid category"}))

              {:error, changeset} ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(400, Jason.encode!(%{error: inspect(changeset)}))
            end
          else
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "model is not enabled or incompatible"}))
          end

        {:error, :not_found} ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{error: "provider not found"}))
      end
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(400, Jason.encode!(%{error: "provider and model are required"}))
    end
  end

  # Scheduler
  get "/api/v1/scheduler" do
    SchedulerHandler.handle_list(conn)
  end

  post "/api/v1/scheduler/scan" do
    SchedulerHandler.handle_scan(conn)
  end

  delete "/api/v1/scheduler/:id" do
    SchedulerHandler.handle_cancel(conn, id)
  end

  # Webhook (Telegram)
  post "/api/v1/webhook/telegram" do
    WebhookHandler.handle_telegram(conn, conn.body_params)
  end

  # Webhook (Discord)
  post "/api/v1/channels/discord/webhook" do
    DiscordWebhookHandler.handle_webhook(conn, conn.body_params)
  end

  # Webhook (Feishu)
  post "/api/v1/channels/feishu/webhook" do
    FeishuWebhookHandler.handle_webhook(conn, conn.body_params)
  end

  # Webhook (WeChat — bridge)
  post "/api/v1/channels/wechat/webhook" do
    WechatWebhookHandler.handle_webhook(conn, conn.body_params)
  end

  # Webhook (WhatsApp — bridge)
  post "/api/v1/channels/whatsapp/webhook" do
    WhatsappWebhookHandler.handle_webhook(conn, conn.body_params)
  end

  # Tools
  get "/api/v1/tools" do
    ToolsHandler.handle_list(conn)
  end

  # User Prompts
  get "/api/v1/user-prompts" do
    UserPromptsHandler.handle_list(conn)
  end

  get "/api/v1/user-prompts/:id" do
    UserPromptsHandler.handle_get(conn, id)
  end

  post "/api/v1/user-prompts" do
    UserPromptsHandler.handle_create(conn)
  end

  put "/api/v1/user-prompts/:id" do
    UserPromptsHandler.handle_update(conn, id)
  end

  delete "/api/v1/user-prompts/:id" do
    UserPromptsHandler.handle_delete(conn, id)
  end

  post "/api/v1/user-prompts/:id/render" do
    UserPromptsHandler.handle_render(conn, id)
  end

  # ── Artifacts ─────────────────────────────────
  get "/api/v1/artifacts" do
    ArtifactHandler.handle_list(conn, conn.params)
  end

  get "/api/v1/artifacts/:id" do
    ArtifactHandler.handle_get(conn, id)
  end

  post "/api/v1/artifacts" do
    ArtifactHandler.handle_create(conn, conn.body_params)
  end

  put "/api/v1/artifacts/:id" do
    ArtifactHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/artifacts/:id" do
    ArtifactHandler.handle_delete(conn, id)
  end

  # ── Automation Rules ────────────────────────────
  get "/api/v1/automation_rules" do
    SchedulesHandler.handle_list(conn, conn.params)
  end

  post "/api/v1/automation_rules/scan" do
    SchedulesHandler.handle_scan(conn)
  end

  get "/api/v1/automation_rules/:id/runs" do
    SchedulesHandler.handle_runs(conn, id, conn.params)
  end

  get "/api/v1/automation_rules/:id" do
    SchedulesHandler.handle_get(conn, id)
  end

  post "/api/v1/automation_rules" do
    SchedulesHandler.handle_create(conn, conn.body_params)
  end

  put "/api/v1/automation_rules/:id" do
    SchedulesHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/automation_rules/:id" do
    SchedulesHandler.handle_delete(conn, id)
  end

  # ── Context Links ──────────────────────────────
  get "/api/v1/context_links" do
    ContextLinkHandler.handle_list(conn, conn.params)
  end

  get "/api/v1/context_links/:id" do
    ContextLinkHandler.handle_get(conn, id)
  end

  post "/api/v1/context_links" do
    ContextLinkHandler.handle_create(conn, conn.body_params)
  end

  delete "/api/v1/context_links/:id" do
    ContextLinkHandler.handle_delete(conn, id)
  end

  # ── Memory ────────────────────────────────────
  get "/api/v1/memory" do
    MemoryHandler.handle_list(conn, conn.params)
  end

  post "/api/v1/memory" do
    MemoryHandler.handle_create(conn, conn.body_params)
  end

  get "/api/v1/memory/:id" do
    MemoryHandler.handle_get(conn, id)
  end

  put "/api/v1/memory/:id" do
    MemoryHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/memory/:id" do
    MemoryHandler.handle_delete(conn, id)
  end

  # ── Metrics ────────────────────────────────────
  get "/api/v1/metrics" do
    MetricsHandler.handle_get(conn)
  end

  get "/api/v1/metrics/spans" do
    MetricsHandler.handle_get_spans(conn)
  end

  # ── Goals ──────────────────────────────────────────
  get "/api/v1/goals" do
    GoalsHandler.handle_list(conn, conn.params)
  end

  post "/api/v1/goals/scan" do
    GoalsHandler.handle_scan(conn)
  end

  get "/api/v1/goals/:id/memories" do
    GoalsHandler.handle_memories(conn, id, conn.params)
  end

  get "/api/v1/goals/:id" do
    GoalsHandler.handle_get(conn, id)
  end

  get "/api/v1/goals/:id/runs" do
    GoalsHandler.handle_runs(conn, id, conn.params)
  end

  get "/api/v1/goals/:id/events" do
    GoalsHandler.handle_get_events(conn, id, conn.params)
  end

  post "/api/v1/goals" do
    GoalsHandler.handle_create(conn, conn.body_params)
  end

  put "/api/v1/goals/:id" do
    GoalsHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/goals/:id" do
    GoalsHandler.handle_delete(conn, id)
  end

  # ── Goal Tasks ─────────────────────────────────────
  get "/api/v1/goals/:goal_id/tasks" do
    GoalTasksHandler.handle_list(conn, %{"goal_id" => goal_id})
  end

  post "/api/v1/goals/:goal_id/tasks" do
    GoalTasksHandler.handle_create(conn, Map.put(conn.body_params, "goal_id", goal_id))
  end

  get "/api/v1/tasks" do
    GoalTasksHandler.handle_list_all(conn)
  end

  get "/api/v1/tasks/:id" do
    GoalTasksHandler.handle_get(conn, id)
  end

  get "/api/v1/tasks/:id/events" do
    GoalTasksHandler.handle_get_events(conn, id, conn.params)
  end

  put "/api/v1/tasks/:id" do
    GoalTasksHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/tasks/:id" do
    GoalTasksHandler.handle_delete(conn, id)
  end

  # ── Planning ───────────────────────────────────────
  post "/api/v1/planning/plan" do
    PlanningHandler.handle_plan(conn, conn.body_params)
  end

  post "/api/v1/planning/replan/:id" do
    PlanningHandler.handle_replan(conn, id, conn.body_params)
  end

  # ── File upload / multimodal support ──────────────
  post "/api/v1/files/upload" do
    AIBrain.Web.Handlers.FilesHandler.handle_upload(conn, conn.params)
  end

  get "/api/v1/files/:id" do
    AIBrain.Web.Handlers.FilesHandler.handle_get(conn, id)
  end

  # 文件系统目录浏览
  get "/api/v1/fs" do
    FsHandler.handle_list(conn)
  end

  # 文件读取（预览用）
  get "/api/v1/file/read" do
    FsHandler.handle_read(conn)
  end

  # ── Skills ────────────────────────────────
  get "/api/v1/skills" do
    AssistantsHandler.handle_list_skills(conn)
  end

  post "/api/v1/skills" do
    AssistantsHandler.handle_create_skill(conn, conn.body_params)
  end

  post "/api/v1/skills/install" do
    AssistantsHandler.handle_install_skill(conn, conn.body_params)
  end

  get "/api/v1/skills/:name" do
    AssistantsHandler.handle_get_skill(conn, name)
  end

  put "/api/v1/skills/:name" do
    AssistantsHandler.handle_update_skill(conn, name, conn.body_params)
  end

  post "/api/v1/skills/:name/update" do
    AssistantsHandler.handle_update_from_source(conn, name)
  end

  post "/api/v1/skills/:name/toggle" do
    AssistantsHandler.handle_toggle_skill(conn, name)
  end

  delete "/api/v1/skills/:name" do
    AssistantsHandler.handle_delete_skill(conn, name)
  end

  # ── Unified Channel Configs ────────────────────────
  get "/api/v1/channels/configs" do
    ChannelConfigHandler.handle_list(conn, conn.params)
  end

  get "/api/v1/channels/configs/:id" do
    ChannelConfigHandler.handle_get(conn, id, conn.params)
  end

  post "/api/v1/channels/configs" do
    ChannelConfigHandler.handle_create(conn, conn.body_params)
  end

  put "/api/v1/channels/configs/:id" do
    ChannelConfigHandler.handle_update(conn, id, conn.body_params)
  end

  delete "/api/v1/channels/configs/:id" do
    ChannelConfigHandler.handle_delete(conn, id)
  end

  # ── TTS (Text-to-Speech) ────────────────────
  get "/api/v1/tts/config" do
    AIBrain.Web.Handlers.TTSHandler.handle_get_config(conn)
  end

  put "/api/v1/tts/config" do
    AIBrain.Web.Handlers.TTSHandler.handle_update_config(conn, conn.body_params)
  end

  get "/api/v1/tts/voices" do
    AIBrain.Web.Handlers.TTSHandler.handle_voices(conn)
  end

  get "/api/v1/tts/languages" do
    AIBrain.Web.Handlers.TTSHandler.handle_languages(conn)
  end

  post "/api/v1/tts/synthesize" do
    AIBrain.Web.Handlers.TTSHandler.handle_synthesize(conn, conn.body_params)
  end

  get "/api/v1/audio/:filename" do
    AIBrain.Web.Handlers.TTSHandler.handle_get_audio(conn, filename)
  end

  # ── STT (Speech-to-Text) ────────────────────
  post "/api/v1/stt/transcribe" do
    AIBrain.Web.Handlers.STTHandler.handle_transcribe(conn, conn.body_params)
  end

  get "/api/v1/stt/status" do
    AIBrain.Web.Handlers.STTHandler.handle_status(conn)
  end

  get "/api/v1/stt/models" do
    AIBrain.Web.Handlers.STTHandler.handle_list_models(conn)
  end

  post "/api/v1/stt/models/:name/download" do
    AIBrain.Web.Handlers.STTHandler.handle_download_model(conn, name)
  end

  delete "/api/v1/stt/models/:name" do
    AIBrain.Web.Handlers.STTHandler.handle_delete_model(conn, name)
  end

  # ── Channel Messages (unified timeline) ─────
  get "/api/v1/channels/:adapter/:channel_id/messages" do
    ChannelsHandler.handle_get_messages(conn, adapter, channel_id)
  end

  # ── Plugins ─────────────────────────────────
  get "/api/v1/plugins" do
    AIBrain.Web.Handlers.PluginsHandler.handle_list(conn)
  end

  get "/api/v1/plugins/:name" do
    AIBrain.Web.Handlers.PluginsHandler.handle_get(conn, name)
  end

  post "/api/v1/plugins/install" do
    AIBrain.Web.Handlers.PluginsHandler.handle_install(conn, conn.body_params)
  end

  post "/api/v1/plugins/:name/enable" do
    AIBrain.Web.Handlers.PluginsHandler.handle_enable(conn, name)
  end

  post "/api/v1/plugins/:name/disable" do
    AIBrain.Web.Handlers.PluginsHandler.handle_disable(conn, name)
  end

  post "/api/v1/plugins/:name/uninstall" do
    AIBrain.Web.Handlers.PluginsHandler.handle_uninstall(conn, name)
  end

  post "/api/v1/plugins/:name/update" do
    AIBrain.Web.Handlers.PluginsHandler.handle_update(conn, name)
  end

  # ── Google OAuth ────────────────────────────────────
  get "/api/v1/auth/google" do
    AIBrain.Web.Handlers.GoogleAuthHandler.handle_authorize(conn)
  end

  get "/api/v1/auth/google/callback" do
    AIBrain.Web.Handlers.GoogleAuthHandler.handle_callback(conn, conn.params)
  end

  get "/api/v1/auth/google/status" do
    AIBrain.Web.Handlers.GoogleAuthHandler.handle_status(conn)
  end

  post "/api/v1/auth/google/disconnect" do
    AIBrain.Web.Handlers.GoogleAuthHandler.handle_disconnect(conn)
  end

  # 404 — API routes: return JSON error
  # Non-API routes (SPA routes): serve index.html for client-side routing
  match _ do
    if !String.starts_with?(conn.request_path, "/api/") do
      static_dir =
        Application.get_env(:ai_brain, :static_dir) ||
          Application.app_dir(:ai_brain, "priv/static")

      index_path = Path.join(static_dir, "index.html")

      if File.exists?(index_path) do
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, File.read!(index_path))
      else
        send_resp(conn, 404, Jason.encode!(%{error: "Not Found", path: conn.request_path}))
      end
    else
      send_resp(conn, 404, Jason.encode!(%{error: "Not Found", path: conn.request_path}))
    end
  end
end
