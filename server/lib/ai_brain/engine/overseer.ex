defmodule AIBrain.Engine.Overseer do
  @moduledoc """
  Engine supervision and admission control.

  Wraps a DynamicSupervisor that manages per-transaction Executor processes.
  Provides throttling (max concurrent transactions), startup recovery
  (marks interrupted transactions as failed), and monitoring.
  """

  use GenServer
  require Logger

  alias AIBrain.AgentRuntime.RunLifecycle
  alias AIBrain.Engine.Executor

  @default_max_concurrent System.schedulers_online() * 2

  # ── Client API ──

  @doc "Start the Overseer."
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start a new transaction under the Overseer.

  Returns `{:ok, executor_pid}` on success, `{:error, :at_capacity}` if at limit.
  """
  def start_transaction(server \\ __MODULE__, tx, sink, ctx) do
    GenServer.call(server, {:start_transaction, tx, sink, ctx})
  end

  @doc "List all active transactions as `[{tx_id, pid, status}]`."
  def list_active(server \\ __MODULE__) do
    GenServer.call(server, :list_active)
  end

  @doc "Cancel a running executor by pid."
  def cancel(server \\ __MODULE__, executor_pid) do
    GenServer.call(server, {:cancel, executor_pid})
  end

  @doc "Cancel a transaction by tx_id. Finds the executor process and cancels it."
  def cancel_tx(server \\ __MODULE__, tx_id) do
    GenServer.call(server, {:cancel_tx, tx_id})
  end

  @doc "Get the number of currently running executors."
  def count_active(server \\ __MODULE__) do
    GenServer.call(server, :count_active)
  end

  # ── Callbacks ──

  @impl true
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)
    name = Keyword.get(opts, :name, __MODULE__)

    recover? =
      Keyword.get(opts, :recover, Application.get_env(:ai_brain, :engine_recovery_enabled, true))

    # DynamicSupervisor for per-transaction Executors
    sup_name = :"#{name}.ExecutorSupervisor"

    children = [
      {DynamicSupervisor, [strategy: :one_for_one, name: sup_name]}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one) do
      {:ok, sup_pid} ->
        state = %{
          sup_pid: sup_pid,
          executor_supervisor: Process.whereis(sup_name),
          max_concurrent: max_concurrent
        }

        if recover? do
          {:ok, state, {:continue, :recover}}
        else
          {:ok, state}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:recover, state) do
    recovery_count = recover_transactions()

    Logger.info(
      "Engine.Overseer: recovered #{recovery_count} transaction(s) from previous session"
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_transaction, tx, sink, ctx}, _from, state) do
    active_count = count_executors(state.executor_supervisor)

    if active_count >= state.max_concurrent do
      Logger.warning(
        "Overseer: at capacity (#{active_count}/#{state.max_concurrent}), rejecting #{tx.id}"
      )

      {:reply, {:error, :at_capacity}, state}
    else
      caller_pid = Map.get(ctx, :caller, self())

      child_spec = %{
        id: Executor,
        start: {Executor, :start_link, [[tx: tx, sink: sink, ctx: ctx, caller: caller_pid]]},
        restart: :temporary,
        type: :worker
      }

      case DynamicSupervisor.start_child(state.executor_supervisor, child_spec) do
        {:ok, pid} ->
          {:reply, {:ok, pid}, state}

        {:ok, pid, _info} ->
          {:reply, {:ok, pid}, state}

        {:error, reason} ->
          Logger.error("Overseer: failed to start executor for #{tx.id}: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:list_active, _from, state) do
    {:reply, list_executors(state.executor_supervisor), state}
  end

  @impl true
  def handle_call(:count_active, _from, state) do
    {:reply, count_executors(state.executor_supervisor), state}
  end

  @impl true
  def handle_call({:cancel, pid}, _from, state) do
    if Process.alive?(pid) do
      Executor.cancel(pid)
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:cancel_tx, tx_id}, _from, state) do
    case find_executor_by_tx_id(state.executor_supervisor, tx_id) do
      {:ok, pid} ->
        Executor.cancel(pid)
        {:reply, :ok, state}

      :not_found ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # ── Recovery ──

  defp recover_transactions do
    try do
      ids = AIBrain.AgentRuntime.RunSink.list_running()
      Logger.info("Overseer: found #{length(ids)} interrupted unified run(s)")
      RunLifecycle.recover_interrupted()
      length(ids)
    rescue
      e ->
        Logger.warning("Overseer: recovery check failed: #{Exception.message(e)}")
        0
    end
  end

  # ── Helpers ──

  defp count_executors(sup) do
    sup
    |> DynamicSupervisor.which_children()
    |> Enum.count(fn {_, pid, _, _} -> pid != nil && Process.alive?(pid) end)
  end

  defp list_executors(sup) do
    sup
    |> DynamicSupervisor.which_children()
    |> Enum.filter(fn {_, pid, _, _} -> pid != nil && Process.alive?(pid) end)
    |> Enum.map(fn {_, pid, _, _} ->
      case GenServer.call(pid, :status) do
        {:ok, tx} -> {tx.id, pid, tx.status}
        _ -> {"unknown", pid, :unknown}
      end
    end)
  rescue
    _ -> []
  end

  defp find_executor_by_tx_id(sup, tx_id) do
    sup
    |> DynamicSupervisor.which_children()
    |> Enum.find_value(fn {_, pid, _, _} ->
      if pid != nil && Process.alive?(pid) do
        case GenServer.call(pid, :status) do
          {:ok, tx} when tx.id == tx_id -> {:ok, pid}
          _ -> nil
        end
      end
    end) || :not_found
  rescue
    _ -> :not_found
  end
end
