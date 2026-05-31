defmodule AIBrain.Session.Registry do
  @moduledoc """
  Registry for tracking running session processes.

  Stores session_id → pid mappings for active sessions,
  allowing abort operations to find and terminate them.
  """

  use GenServer
  require Logger

  @table_name :session_registry

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def register(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register, session_id, pid})
  end

  def try_register(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:try_register, session_id, pid})
  end

  def unregister(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:unregister, session_id})
  end

  def get_pid(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:get_pid, session_id})
  end

  def abort(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:abort, session_id})
  end

  def is_running?(session_id) when is_binary(session_id) do
    GenServer.call(__MODULE__, {:is_running, session_id})
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, session_id, pid}, _from, state) do
    # If already registered, demonitor the old process to prevent monitor leaks.
    # Log a warning — duplicate registrations indicate a client-side bug (concurrent
    # sends for the same session).
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, old_pid, old_ref}] ->
        Process.demonitor(old_ref, [:flush])

        Logger.warning(
          "Session #{session_id} was already registered (old pid: #{inspect(old_pid)}), replacing with #{inspect(pid)}"
        )

      [] ->
        :ok
    end

    ref = Process.monitor(pid)
    :ets.insert(@table_name, {session_id, pid, ref})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:try_register, session_id, pid}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, existing_pid, _ref}] ->
        if Process.alive?(existing_pid) do
          {:reply, {:error, :already_running}, state}
        else
          :ets.delete(@table_name, session_id)
          register_session(session_id, pid)
          {:reply, :ok, state}
        end

      [] ->
        register_session(session_id, pid)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:unregister, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, _pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(@table_name, session_id)
        Logger.debug("Unregistered session #{session_id}")

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_pid, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, pid, _ref}] ->
        {:reply, {:ok, pid}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:abort, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, pid, _ref}] ->
        if Process.alive?(pid) do
          send(pid, :__abort_session__)
          # Also kill the process to stop any in-flight LLM requests
          Process.exit(pid, :session_aborted)
          Process.send_after(self(), {:cleanup_check, session_id}, 5_000)
          Logger.info("Session #{session_id} aborted and process killed")
          {:reply, :ok, state}
        else
          :ets.delete(@table_name, session_id)
          {:reply, {:error, :already_dead}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:is_running, session_id}, _from, state) do
    result =
      case :ets.lookup(@table_name, session_id) do
        [{^session_id, pid, _ref}] -> Process.alive?(pid)
        [] -> false
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {session_id, pid, _ref} ->
        %{session_id: session_id, pid: inspect(pid), alive: Process.alive?(pid)}
      end)

    {:reply, sessions, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    :ets.match_delete(@table_name, {:_, :_, ref})
    {:noreply, state}
  end

  @impl true
  def handle_info({:cleanup_check, session_id}, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, pid, _ref}] ->
        if Process.alive?(pid) do
          Logger.warning(
            "Session #{session_id} did not shut down gracefully within timeout, keeping registry entry"
          )

          {:noreply, state}
        else
          :ets.delete(@table_name, session_id)
          Logger.info("Session #{session_id} registry entry cleaned up after shutdown")
          {:noreply, state}
        end

      [] ->
        {:noreply, state}
    end
  end

  defp register_session(session_id, pid) do
    ref = Process.monitor(pid)
    :ets.insert(@table_name, {session_id, pid, ref})
  end
end
