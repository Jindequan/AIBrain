defmodule AIBrain.Notification.Router do
  @moduledoc """
  Central notification router that listens to Bus events and routes them
  to the appropriate notification channels.

  Subscribes to Channel.Bus global events and translates system-level
  events (task completed, task failed, approval needed, etc.) into
  user-facing notifications via:
    1. Desktop notifications (macOS/Linux via notify tool)
    2. NotificationQueue (persistent, retried)
    3. Channel.Gateway (Telegram, etc.)

  Started under the main Application supervisor tree.
  """

  use GenServer
  require Logger

  alias AIBrain.Channel.Bus
  alias AIBrain.Data.NotificationQueue

  # Events that warrant immediate desktop notification
  @desktop_notify_events ~w(
    task_completed task_failed goal_completed goal_failed
    proxy_escalated interaction_escalated interaction_expired
    automation_triggered scheduler_fired
  )a

  # Events that should be persisted to NotificationQueue
  @persist_events ~w(
    task goal approval run
  )a

  # ── Client API ──

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Manually send a notification through all channels."
  def notify(title, message, opts \\ []) do
    router = Keyword.get(opts, :router, __MODULE__)
    GenServer.call(router, {:notify, title, message, opts})
  end

  # ── Callbacks ──

  @impl true
  def init(opts) do
    # Subscribe to global Bus events (safe — won't crash if Bus not started)
    # Must pass self() not __MODULE__ because Bus stores pids and uses Process.alive?
    try do
      Bus.subscribe(self())
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    desktop_enabled = Keyword.get(opts, :desktop_notifications, true)
    Logger.info("NotificationRouter started (desktop: #{desktop_enabled})")
    {:ok, %{desktop_enabled: desktop_enabled}}
  end

  @impl true
  def handle_call({:notify, title, message, opts}, _from, state) do
    result = dispatch_notification(title, message, opts, state)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:bus_message, event}, state) when is_map(event) do
    handle_bus_event(event, state)
    {:noreply, state}
  end

  # Catch-all for bus messages we don't care about
  def handle_info({:bus_message, _}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Event Handling ──

  defp handle_bus_event(%{type: event_type} = event, state) do
    type_key = if is_atom(event_type), do: event_type, else: String.to_atom("#{event_type}")

    if type_key in @desktop_notify_events or type_key in @persist_events do
      {title, message, opts} = translate_event(type_key, event)
      dispatch_notification(title, message, opts, state)
    end
  rescue
    e ->
      Logger.warning(
        "NotificationRouter: failed to handle event #{inspect(event_type)}: #{Exception.message(e)}"
      )
  end

  defp handle_bus_event(_, _), do: :ok

  # ── Event Translation ──

  defp translate_event(:task_completed, event) do
    task_title = event[:title] || event[:task_title] || "任务"
    {"✅ 任务完成", "#{task_title} 已完成", [priority: :low, category: :task, task_id: event[:task_id]]}
  end

  defp translate_event(:task_failed, event) do
    task_title = event[:title] || event[:task_title] || "任务"
    reason = event[:reason] || "未知原因"

    {"❌ 任务失败", "#{task_title}: #{truncate(reason, 100)}",
     [priority: :high, category: :task, task_id: event[:task_id]]}
  end

  defp translate_event(:goal_completed, event) do
    {"🎯 目标完成", "所有任务已完成", [priority: :normal, category: :goal, goal_id: event[:goal_id]]}
  end

  defp translate_event(:goal_failed, event) do
    {"⚠️ 目标失败", "部分任务执行失败", [priority: :high, category: :goal, goal_id: event[:goal_id]]}
  end

  defp translate_event(:approval_needed, event) do
    tool = event[:tool_name] || event[:tool] || "工具"

    {"🔐 需要审批", "Agent 请求使用 #{tool}",
     [priority: :high, category: :approval, approval_id: event[:approval_id]]}
  end

  defp translate_event(:run_completed, event) do
    run_id = event[:run_id] || "unknown"
    {"🏃 运行完成", "后台任务 #{truncate(run_id, 8)} 完成", [priority: :low, category: :run, run_id: run_id]}
  end

  defp translate_event(:run_failed, event) do
    run_id = event[:run_id] || "unknown"
    reason = event[:reason] || "未知"

    {"💥 运行失败", "后台任务 #{truncate(run_id, 8)}: #{truncate(reason, 80)}",
     [priority: :high, category: :run, run_id: run_id]}
  end

  defp translate_event(:automation_triggered, event) do
    rule_name = event[:rule_name] || "自动化规则"
    {"⚡ 自动化触发", rule_name, [priority: :low, category: :automation]}
  end

  defp translate_event(:scheduler_fired, event) do
    task_name = event[:name] || "定时任务"
    {"⏰ 定时触发", task_name, [priority: :low, category: :scheduler]}
  end

  defp translate_event(:proxy_escalated, event) do
    reason = event[:reason] || event[:data][:reason] || "需要你的关注"
    {"🤖 Proxy 升级", String.slice(reason, 0, 200), [priority: :high, category: :proxy]}
  end

  defp translate_event(:interaction_escalated, event) do
    reason = event[:reason] || "Proxy 无法处理此交互"
    {"🤖 Proxy 升级交互", String.slice(reason, 0, 200), [priority: :high, category: :proxy]}
  end

  defp translate_event(:interaction_expired, event) do
    type = event[:interaction_type] || "unknown"
    {"⏰ 交互已超时", "类型: #{type}", [priority: :high, category: :proxy]}
  end

  defp translate_event(type, event) do
    {"📢 系统通知", "#{type}: #{inspect(event) |> truncate(80)}", [priority: :low]}
  end

  # ── Dispatch ──

  defp dispatch_notification(title, message, opts, state) do
    category = Keyword.get(opts, :category)
    priority = Keyword.get(opts, :priority, :normal)

    # 1. Desktop notification (immediate, fire-and-forget)
    if state.desktop_enabled and priority in [:high, :normal] do
      send_desktop_notification(title, message)
    end

    # 2. Persist to NotificationQueue (for history & retry)
    if category in @persist_events do
      persist_notification(title, message, opts)
    end

    # 3. Route through Channel.Gateway (Telegram, etc.) for high-priority
    if priority == :high do
      route_to_channels(title, message, opts)
    end

    :ok
  rescue
    e ->
      Logger.warning("NotificationRouter dispatch failed: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp send_desktop_notification(title, message) do
    # Use the notify tool's underlying mechanism directly
    Task.start(fn ->
      try do
        AIBrain.Tool.Builtin.Notify.execute(
          %{"title" => title, "message" => message},
          %{}
        )
      rescue
        _ -> :ok
      end
    end)
  end

  defp persist_notification(title, message, opts) do
    Task.start(fn ->
      try do
        NotificationQueue.create(%{
          id: "notif-#{System.unique_integer([:positive])}",
          channel: "desktop",
          status: "pending",
          payload: %{
            title: title,
            message: message,
            category: to_string(opts[:category] || "system"),
            priority: to_string(opts[:priority] || "normal"),
            metadata: build_metadata(opts)
          }
        })
      rescue
        e ->
          Logger.warning(
            "NotificationRouter: failed to persist notification: #{Exception.message(e)}"
          )
      end
    end)
  end

  defp route_to_channels(title, message, opts) do
    Task.start(fn ->
      try do
        # Publish to Channel Bus for channel adapters to pick up
        Bus.publish(__MODULE__, %{
          type: :user_notification,
          title: title,
          message: message,
          category: opts[:category],
          metadata: build_metadata(opts)
        })
      rescue
        e ->
          Logger.warning(
            "NotificationRouter: failed to route to channels: #{Exception.message(e)}"
          )
      end
    end)
  end

  defp build_metadata(opts) do
    keys = [:task_id, :goal_id, :run_id, :approval_id, :session_id, :rule_name]

    for key <- keys, val = Keyword.get(opts, key), val != nil, into: %{} do
      {key, val}
    end
  end

  defp truncate(str, max) when is_binary(str) do
    if byte_size(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  defp truncate(other, max), do: truncate(inspect(other), max)
end
