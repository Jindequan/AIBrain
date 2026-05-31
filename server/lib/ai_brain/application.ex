defmodule AIBrain.Application do
  @moduledoc """
  AIBrain application entry point. Starts core services and HTTP server.
  """

  use Application
  require Logger

  def start(_type, _args) do
    # Allow STATIC_DIR env var to override the static files directory at runtime.
    # Used by the Electron main.cjs which sets this to the bundled dist path.
    if static_dir = System.get_env("STATIC_DIR") do
      Application.put_env(:ai_brain, :static_dir, static_dir)
    end

    port = get_port()
    ensure_data_dir()
    AIBrain.Session.EventBuffer.init_tables()

    session_store =
      Application.get_env(:ai_brain, :session_store, AIBrain.Session.Store.Memory)

    children =
      [
        # Task supervisor for background jobs
        {Task.Supervisor, name: AIBrain.TaskSupervisor},
        # Database — must be first, all services depend on it
        AIBrain.Repo,
        # Migrations must run before services query schemas during init/recovery.
        {AIBrain.MigrationRunner, []},
        # Core services

        {AIBrain.Tool.Registry, [name: AIBrain.Tool.Registry]},
        {AIBrain.Tool.Executor, [registry: AIBrain.Tool.Registry, name: AIBrain.Tool.Executor]},
        # Provider Registry — ETS-backed with JSON persistence
        {AIBrain.Provider.Registry, [name: AIBrain.Provider.Registry]},
        # Notification gateway
        {AIBrain.Channel.Bus, [name: AIBrain.Channel.Bus]},
        {AIBrain.Channel.EventStore, [name: AIBrain.Channel.EventStore]},
        {AIBrain.Channel.DispatchQueue, [name: AIBrain.Channel.DispatchQueue]},
        {AIBrain.Channel.Gateway,
         [
           adapters: Application.get_env(:ai_brain, :gateway_adapters, []),
           name: AIBrain.Channel.Gateway
         ]},
        # Skill registry
        {AIBrain.Skill.Registry, [name: AIBrain.Skill.Registry]},
        # Knowledge system — scientific, engineering, methodology knowledge
        {AIBrain.Knowledge.Registry, [name: AIBrain.Knowledge.Registry]},
        # Plugin registry
        {AIBrain.Plugin.Registry, [name: AIBrain.Plugin.Registry]},
        # Engine supervision and admission control
        {AIBrain.Engine.Overseer, [name: AIBrain.Engine.Overseer]},
        # User interaction manager — approval, clarification and confirmation lifecycle
        {AIBrain.Interaction.Manager, [name: AIBrain.Interaction.Manager]},
        # Notification routing — listens to Bus events and dispatches user notifications
        {AIBrain.Notification.Router, [name: AIBrain.Notification.Router]},
        {AIBrain.Session.Registry, []},
        {AIBrain.Session.StreamManager, []},
        # Telemetry
        {AIBrain.Telemetry.Reporter, []}
      ]
      |> maybe_add_background_services()

    children =
      if Application.get_env(:ai_brain, :proxy_enabled, true) do
        insert_after(
          children,
          AIBrain.Interaction.Manager,
          {AIBrain.Proxy, [name: AIBrain.Proxy]}
        )
      else
        children
      end

    children =
      if Application.get_env(:ai_brain, :dev_reloader, false) do
        children ++ [{AIBrain.DevReloader, []}]
      else
        children
      end

    children =
      if Application.get_env(:ai_brain, :disable_http, false) do
        children
      else
        children ++
          [
            {session_store, [name: session_store]},
            {AIBrain.Provider.Router, [name: AIBrain.Provider.Router]},
            {Plug.Cowboy, scheme: :http, plug: AIBrain.Web.Server, options: [port: port]},
            {Plug.Cowboy.Drainer, refs: [AIBrain.Web.Server.HTTP], shutdown: 15_000}
          ]
      end

    opts = [strategy: :one_for_one, max_restarts: 10, max_seconds: 30, name: AIBrain.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, _pid} ->
        if Application.get_env(:ai_brain, :startup_jobs_enabled, true) do
          start_deferred_startup_jobs()
          schedule_episodic_batch()
        end

        Logger.info("AIBrain API Server started on http://localhost:#{port}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start AIBrain: #{inspect(reason)}")
    end

    result
  end

  def stop(_state) do
    try do
      Ecto.Adapters.SQL.query!(AIBrain.Repo, "PRAGMA wal_checkpoint(TRUNCATE)", [])
      Logger.info("WAL checkpoint completed on shutdown")
    rescue
      e -> Logger.warning("WAL checkpoint failed: #{Exception.message(e)}")
    end

    :ok
  end

  defp ensure_data_dir do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    File.mkdir_p!(data_dir)
    File.mkdir_p!(Path.join(data_dir, "sessions"))
    File.mkdir_p!(Path.join(data_dir, "workspace"))
    File.mkdir_p!(Path.join(data_dir, "backups"))
    File.mkdir_p!(Path.join(data_dir, "skills"))
  end

  defp get_port do
    env_port = System.get_env("AIBRAIN_PORT") || System.get_env("PORT")

    if env_port,
      do: String.to_integer(env_port),
      else: Application.get_env(:ai_brain, :port, 4100)
  end

  defp insert_after(children, target_module, child_spec) do
    {left, right} =
      Enum.split_while(children, fn
        {^target_module, _opts} -> false
        ^target_module -> false
        _ -> true
      end)

    case right do
      [] -> children ++ [child_spec]
      [target | rest] -> left ++ [target, child_spec | rest]
    end
  end

  defp maybe_add_background_services(children) do
    if Application.get_env(:ai_brain, :background_services_enabled, true) do
      children ++
        [
          {AIBrain.Task.RegistryWatcher, []},
          {AIBrain.Monitor, [name: AIBrain.Monitor]},
          {AIBrain.Task.AutomationEngine,
           [name: AIBrain.Task.AutomationEngine, scan_interval: 60]},
          {AIBrain.AgentRuntime.GoalDaemon, [name: AIBrain.AgentRuntime.GoalDaemon]},
          {AIBrain.Task.Dispatcher,
           [
             name: AIBrain.Task.Dispatcher,
             enabled: Application.get_env(:ai_brain, :task_dispatcher_enabled, true)
           ]},
          {AIBrain.Job.NotificationCleanup, [name: AIBrain.Job.NotificationCleanup]},
          {AIBrain.Memory.Distiller, [name: AIBrain.Memory.Distiller]}
        ]
    else
      children
    end
  end

  defp start_deferred_startup_jobs do
    spawn(fn ->
      try do
        AIBrain.TelegramConfigLoader.load_and_register()
      rescue
        e -> Logger.warning("Channel config load deferred: #{Exception.message(e)}")
      catch
        :exit, _ -> :ok
      end
    end)

    spawn(fn ->
      try do
        AIBrain.Web.Handlers.GoogleAuthHandler.load_tokens_into_env()
      rescue
        e -> Logger.warning("Google token load deferred: #{Exception.message(e)}")
      catch
        :exit, _ -> :ok
      end
    end)

    spawn(fn ->
      try do
        AIBrain.Tool.Discovery.register_builtin_tools(AIBrain.Tool.Registry)
        AIBrain.Plugin.Installer.register_all_builtin()
        AIBrain.Tool.Executor.reload(AIBrain.Tool.Executor)

        Task.Supervisor.start_child(
          AIBrain.TaskSupervisor,
          &AIBrain.RAG.Ingester.startup_ingest/0
        )
      rescue
        e -> Logger.warning("Tool/Plugin registration deferred: #{Exception.message(e)}")
      catch
        :exit, _ -> :ok
      end
    end)
  end

  defp episodic_batch_loop do
    # 10 minutes
    Process.sleep(600_000)

    try do
      AIBrain.Memory.Distiller.run_episodic_batch()
    rescue
      e -> Logger.warning("Episodic batch failed: #{Exception.message(e)}")
    catch
      :exit, _ -> :ok
    end

    episodic_batch_loop()
  end

  defp schedule_episodic_batch do
    # Use Task.Supervisor so the process is linked and crashes are logged.
    # On crash, schedule_episodic_batch is re-invoked from a timer.
    {:ok, _pid} =
      Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
        episodic_batch_loop()
      end)
  rescue
    e -> Logger.warning("Failed to schedule episodic batch: #{Exception.message(e)}")
  end
end
