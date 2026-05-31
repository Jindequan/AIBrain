defmodule AIBrain.Channel.EventStore do
  @moduledoc """
  Fire-and-forget event persistence side-writer attached to Channel.Bus.

  Listens for published events, filters which should persist, and writes
  them to the events table asynchronously.
  """
  use GenServer
  require Logger

  alias AIBrain.Data.Events

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Persist an event map directly (used for non-Bus sources)."
  def append(event_type, payload, opts \\ []) do
    attrs = %{
      event_type: event_type,
      payload: payload,
      correlation_id: Keyword.get(opts, :correlation_id, Ecto.UUID.generate()),
      source: Keyword.get(opts, :source, "system"),
      session_id: Keyword.get(opts, :session_id),
      goal_id: Keyword.get(opts, :goal_id),
      task_id: Keyword.get(opts, :task_id),
      run_id: Keyword.get(opts, :run_id),
      importance: Keyword.get(opts, :importance, 0.5),
      token_count: Keyword.get(opts, :token_count, 0),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    GenServer.cast(__MODULE__, {:persist, attrs})
  end

  @impl true
  def init(_opts) do
    # Subscribe to Channel.Bus
    try do
      AIBrain.Channel.Bus.subscribe(self())
    rescue
      e ->
        Logger.warning("EventStore: failed to subscribe to Bus: #{Exception.message(e)}")
        :ok
    end

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:persist, attrs}, state) do
    case Events.create(attrs) do
      {:ok, _event} ->
        check_distillation_trigger()
        {:noreply, state}

      {:error, changeset} ->
        Logger.error("EventStore: failed to persist event: #{inspect(changeset.errors)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:bus_event, message}, state) do
    # Fire-and-forget persist from Bus events
    if should_persist?(message) do
      attrs = build_attrs_from_bus(message)
      GenServer.cast(self(), {:persist, attrs})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @persistable_types ~w(
    task_event
    goal_event
    agent_action
    approval_needed
    approval_result
  )a

  # Whitelist: only persist the event types defined in Spec B §1.2.
  defp should_persist?(%{type: type}), do: type in @persistable_types

  defp should_persist?(%{event_type: type}),
    do: to_string(type) in Enum.map(@persistable_types, &to_string/1)

  defp should_persist?(_), do: false

  defp build_attrs_from_bus(message) do
    %{
      event_type: to_string(Map.get(message, :type, "bus_event")),
      payload:
        Map.drop(message, [:type, :correlation_id, :session_id, :goal_id, :task_id, :run_id]),
      correlation_id: Map.get(message, :correlation_id, Ecto.UUID.generate()),
      source: to_string(Map.get(message, :source, "system")),
      session_id: Map.get(message, :session_id),
      goal_id: Map.get(message, :goal_id),
      task_id: Map.get(message, :task_id),
      run_id: Map.get(message, :run_id),
      importance: Map.get(message, :importance, 0.5),
      token_count: Map.get(message, :token_count, 0),
      metadata: Map.get(message, :metadata, %{})
    }
  end

  defp check_distillation_trigger do
    # If >=100 undistilled events, trigger episodic batch processing
    try do
      if AIBrain.Data.Events.count_undistilled() >= 100 do
        Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
          AIBrain.Memory.Distiller.run_episodic_batch()
        end)
      end
    rescue
      _ -> :ok
    end
  end
end
