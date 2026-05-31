defmodule AIBrain.Channel.Bus do
  use GenServer

  @moduledoc """
  Outbound channel bus with alert severity tracking and deduplication.

  - Accepts raw maps (backward compatible) and Alert structs
  - Tracks recent alert keys for dedup
  - Forwards non-suppressed alerts to Notifier
  - Maintains a ring buffer of published messages (max 200)
  """

  require Logger

  alias AIBrain.Channel.Alert

  @max_messages 200
  @max_alert_history 500
  @cleanup_interval_ms 60_000

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, [])
      name -> GenServer.start_link(__MODULE__, [], name: name)
    end
  end

  @doc "Publish a raw message or Alert struct."
  def publish(message) do
    publish(__MODULE__, message)
  end

  def publish(server, %Alert{} = alert) do
    GenServer.call(server, {:publish_alert, alert})
  end

  def publish(server, message) when is_map(message) do
    GenServer.cast(server, {:publish, message})
  end

  @doc "Subscribe a pid to receive published messages."
  def subscribe(server \\ __MODULE__, pid) do
    GenServer.call(server, {:subscribe, pid})
  end

  @doc "Unsubscribe a pid."
  def unsubscribe(server \\ __MODULE__, pid) do
    GenServer.call(server, {:unsubscribe, pid})
  end

  @doc "Drain all published messages."
  def published(server \\ __MODULE__) do
    GenServer.call(server, :published)
  end

  @doc "Return the last N published messages."
  def recent(server \\ __MODULE__, limit \\ 50) do
    GenServer.call(server, {:recent, limit})
  end

  @doc "Return recent alert history for dedup inspection."
  def alert_history(server \\ __MODULE__) do
    GenServer.call(server, :alert_history)
  end

  @doc "Subscribe current process to events for a specific session."
  def subscribe_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:subscribe_session, session_id, self()})
  end

  @doc "Unsubscribe current process from a session."
  def unsubscribe_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:unsubscribe_session, session_id, self()})
  end

  @doc "Publish an event to all subscribers of a session."
  def publish(server \\ __MODULE__, session_id, event)
      when is_binary(session_id) and is_map(event) do
    GenServer.call(server, {:publish_session, session_id, event})
  end

  @doc "Subscribe current process to events for a specific run."
  def subscribe_run(server \\ __MODULE__, run_id) do
    GenServer.call(server, {:subscribe_run, run_id, self()})
  end

  @doc "Unsubscribe current process from a specific run."
  def unsubscribe_run(server \\ __MODULE__, run_id) do
    GenServer.call(server, {:unsubscribe_run, run_id, self()})
  end

  @doc "Publish an event to all subscribers of a specific run."
  def publish_run(server \\ __MODULE__, run_id, event) when is_binary(run_id) and is_map(event) do
    GenServer.call(server, {:publish_run, run_id, event})
  end

  # ── Callbacks ─────────────────────────────────────────────────────

  @impl true
  def init(_) do
    schedule_cleanup()

    {:ok,
     %{
       messages: [],
       alert_history: [],
       subscribers: MapSet.new(),
       session_subscriptions: %{},
       run_subscriptions: %{}
     }}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_stale, @cleanup_interval_ms)
  end

  @impl true
  def handle_cast({:publish, message}, state) do
    messages = pruned(state.messages ++ [message], @max_messages)
    forward_to_notifier(message)
    notify_subscribers(message, state.subscribers)
    {:noreply, %{state | messages: messages}}
  end

  @impl true
  def handle_call({:publish_alert, %Alert{} = alert}, _from, state) do
    if Alert.suppressed?(alert, state.alert_history) do
      {:reply, {:suppressed, alert.dedup_key}, state}
    else
      now = System.system_time(:millisecond)
      history = [{alert.dedup_key, now} | state.alert_history] |> Enum.take(@max_alert_history)
      messages = pruned(state.messages ++ [alert], @max_messages)

      forward_to_notifier(alert)
      notify_subscribers(alert, state.subscribers)

      {:reply, :ok, %{state | messages: messages, alert_history: history}}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call(:published, _from, state) do
    {:reply, state.messages, %{state | messages: []}}
  end

  @impl true
  def handle_call({:recent, limit}, _from, state) do
    {:reply, Enum.take(state.messages, limit), state}
  end

  @impl true
  def handle_call(:alert_history, _from, state) do
    {:reply, state.alert_history, state}
  end

  @impl true
  def handle_call({:subscribe_session, session_id, pid}, _from, state) do
    Process.monitor(pid)
    current = Map.get(state.session_subscriptions, session_id, MapSet.new())
    new_subs = Map.put(state.session_subscriptions, session_id, MapSet.put(current, pid))
    {:reply, :ok, %{state | session_subscriptions: new_subs}}
  end

  @impl true
  def handle_call({:unsubscribe_session, session_id, pid}, _from, state) do
    current = Map.get(state.session_subscriptions, session_id, MapSet.new())
    updated = MapSet.delete(current, pid)

    new_subs =
      if MapSet.size(updated) == 0,
        do: Map.delete(state.session_subscriptions, session_id),
        else: Map.put(state.session_subscriptions, session_id, updated)

    {:reply, :ok, %{state | session_subscriptions: new_subs}}
  end

  @impl true
  def handle_call({:publish_session, session_id, event}, _from, state) do
    # Buffer for reconnect replay
    AIBrain.Session.EventBuffer.append(session_id, event)

    # Deliver to live subscribers
    pids = Map.get(state.session_subscriptions, session_id, MapSet.new())

    Enum.each(pids, fn pid ->
      send(pid, {:session_event, session_id, event})
    end)

    # Notify global subscribers (EventStore, etc.)
    notify_subscribers(Map.put(event, :session_id, session_id), state.subscribers)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:subscribe_run, run_id, pid}, _from, state) do
    Process.monitor(pid)
    current = Map.get(state.run_subscriptions, run_id, MapSet.new())
    new_subs = Map.put(state.run_subscriptions, run_id, MapSet.put(current, pid))
    {:reply, :ok, %{state | run_subscriptions: new_subs}}
  end

  @impl true
  def handle_call({:unsubscribe_run, run_id, pid}, _from, state) do
    current = Map.get(state.run_subscriptions, run_id, MapSet.new())
    updated = MapSet.delete(current, pid)

    new_subs =
      if MapSet.size(updated) == 0,
        do: Map.delete(state.run_subscriptions, run_id),
        else: Map.put(state.run_subscriptions, run_id, updated)

    {:reply, :ok, %{state | run_subscriptions: new_subs}}
  end

  @impl true
  def handle_call({:publish_run, run_id, event}, _from, state) do
    # Deliver to live subscribers
    pids = Map.get(state.run_subscriptions, run_id, MapSet.new())

    Enum.each(pids, fn pid ->
      send(pid, {:run_event, run_id, event})
    end)

    # Also notify global subscribers (for EventStore logging, etc.)
    notify_subscribers(Map.put(event, :run_id, run_id), state.subscribers)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up global subscriptions
    global_subs = MapSet.delete(state.subscribers, pid)

    # Clean up all session subscriptions
    session_subs =
      state.session_subscriptions
      |> Enum.map(fn {sid, pids} -> {sid, MapSet.delete(pids, pid)} end)
      |> Enum.reject(fn {_sid, pids} -> MapSet.size(pids) == 0 end)
      |> Map.new()

    # Clean up all run subscriptions
    run_subs =
      state.run_subscriptions
      |> Enum.map(fn {rid, pids} -> {rid, MapSet.delete(pids, pid)} end)
      |> Enum.reject(fn {_rid, pids} -> MapSet.size(pids) == 0 end)
      |> Map.new()

    {:noreply,
     %{
       state
       | subscribers: global_subs,
         session_subscriptions: session_subs,
         run_subscriptions: run_subs
     }}
  end

  @impl true
  def handle_info(:cleanup_stale, state) do
    # Periodic sweep: remove dead processes from all subscription maps
    global_subs = Enum.filter(state.subscribers, &Process.alive?/1) |> MapSet.new()

    session_subs =
      state.session_subscriptions
      |> Enum.map(fn {sid, pids} -> {sid, MapSet.filter(pids, &Process.alive?/1)} end)
      |> Enum.reject(fn {_sid, pids} -> MapSet.size(pids) == 0 end)
      |> Map.new()

    run_subs =
      state.run_subscriptions
      |> Enum.map(fn {rid, pids} -> {rid, MapSet.filter(pids, &Process.alive?/1)} end)
      |> Enum.reject(fn {_rid, pids} -> MapSet.size(pids) == 0 end)
      |> Map.new()

    schedule_cleanup()

    {:noreply,
     %{
       state
       | subscribers: global_subs,
         session_subscriptions: session_subs,
         run_subscriptions: run_subs
     }}
  end

  # ── Private ───────────────────────────────────────────────────────

  defp pruned(list, max) when length(list) > max, do: Enum.take(list, -max)
  defp pruned(list, _max), do: list

  defp forward_to_notifier(event) do
    AIBrain.Channel.Notifier.dispatch(event)
  rescue
    e ->
      Logger.warning("Bus: failed to forward to notifier: #{Exception.message(e)}")
      :ok
  end

  defp notify_subscribers(message, subscribers) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:bus_event, message})
    end)
  end
end
