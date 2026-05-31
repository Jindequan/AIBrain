defmodule AIBrain.Provider.Registry do
  @moduledoc """
  ETS-backed GenServer for provider storage and lookups.

  Now integrates with ReqLLM for provider definitions and API key management.
  Local configuration (priorities, model filters) is stored in ~/.aibrain/provider_config.json.

  Migration from old AIBrain provider system:
  - Provider definitions come from ReqLLM (22+ providers, 665+ models)
  - API keys are managed by ReqLLM.put_key/get_key
  - Local enable/disable and priority is stored in provider_config.json
  """

  use GenServer
  require Logger

  alias AIBrain.Config.FileBackend
  alias AIBrain.Config.ProviderConfig
  alias AIBrain.Provider.Adapter
  alias AIBrain.LLM.Provider, as: LLMProvider

  # ── Client API ─────────────────────────────────────────────

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def list(server \\ __MODULE__), do: GenServer.call(server, :list)
  def get(server \\ __MODULE__, name), do: GenServer.call(server, {:get, name})
  def all_providers(server \\ __MODULE__), do: GenServer.call(server, :all_providers)

  def add(server \\ __MODULE__, %AIBrain.Provider.Info{} = provider) do
    GenServer.call(server, {:add, provider})
  end

  def update(server \\ __MODULE__, name, %AIBrain.Provider.Info{} = provider) do
    GenServer.call(server, {:update, name, provider})
  end

  def delete(server \\ __MODULE__, name) do
    GenServer.call(server, {:delete, name})
  end

  # ── GenServer Callbacks ────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(:ai_brain_provider_registry, [:set, :protected, :named_table])

    # Try to load providers from ReqLLM first
    providers =
      case load_providers_from_req_llm() do
        providers when is_list(providers) and length(providers) > 0 ->
          Logger.info("Loaded #{length(providers)} providers from ReqLLM")
          providers

        _ ->
          # Fallback to legacy system and attempt migration
          Logger.info("Attempting to load legacy providers and migrate to ReqLLM...")
          legacy_providers = FileBackend.load_providers()

          if length(legacy_providers) > 0 do
            Logger.info("Found #{length(legacy_providers)} legacy providers, migrating...")

            case Adapter.migrate_old_config() do
              :ok ->
                Logger.info("Successfully migrated legacy providers")
                # After migration, try loading from ReqLLM again
                case load_providers_from_req_llm() do
                  migrated when is_list(migrated) -> migrated
                  _ -> legacy_providers
                end

              {:error, reason} ->
                Logger.warning("Migration failed: #{inspect(reason)}, using legacy providers")
                legacy_providers
            end
          else
            []
          end
      end

    for p <- providers, do: :ets.insert(table, {p.name, p})
    Logger.info("Provider.Registry initialized with #{length(providers)} providers")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    providers = tab2list(state.table) |> Enum.filter(& &1.enabled)
    {:reply, providers, state}
  end

  @impl true
  def handle_call({:get, name}, _from, state) do
    case :ets.lookup(state.table, name) do
      [{^name, p}] -> {:reply, {:ok, p}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:all_providers, _from, state) do
    {:reply, tab2list(state.table), state}
  end

  @impl true
  def handle_call({:add, %AIBrain.Provider.Info{} = provider}, _from, state) do
    # Convert to ReqLLM format and store API key
    Adapter.to_req_llm_provider(provider)
    :ets.insert(state.table, {provider.name, provider})
    persist_to_file()
    notify_router()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update, name, %AIBrain.Provider.Info{} = provider}, _from, state) do
    Adapter.to_req_llm_provider(provider)

    if name != provider.name do
      :ets.delete(state.table, name)
    end

    :ets.insert(state.table, {provider.name, provider})
    persist_to_file()
    notify_router()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) do
    :ets.delete(state.table, name)
    ProviderConfig.disable_provider(name)
    persist_to_file()
    notify_router()
    {:reply, :ok, state}
  end

  # ── File Persistence ───────────────────────────────────────

  defp persist_to_file do
    providers = tab2list(:ai_brain_provider_registry)
    # Still save to old format for backward compatibility
    FileBackend.save_providers(providers)
  end

  # ── Provider Loading ───────────────────────────────────────

  defp load_providers_from_req_llm do
    try do
      LLMProvider.list_providers()
      |> Enum.map(fn provider_atom ->
        Adapter.to_provider_info(provider_atom)
      end)
      |> Enum.filter(&(!is_nil(&1)))
    rescue
      e ->
        Logger.error("Error loading providers from ReqLLM: #{inspect(e)}")
        {:error, e}
    end
  end

  # ── Helpers ────────────────────────────────────────────────

  defp tab2list(table) do
    table |> :ets.tab2list() |> Enum.map(fn {_name, p} -> p end)
  end

  defp notify_router do
    case Process.whereis(AIBrain.Provider.Router) do
      nil -> :ok
      pid when is_pid(pid) -> GenServer.cast(pid, :reload_from_file)
    end
  rescue
    _ -> :ok
  end
end
