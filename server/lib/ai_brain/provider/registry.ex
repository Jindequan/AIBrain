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

    providers = load_providers_from_req_llm()

    # One-time migration from legacy providers.json if no ReqLLM providers found
    providers =
      if providers == [] do
        legacy = AIBrain.Config.FileBackend.load_providers()

        if legacy != [] do
          Logger.info("Migrating #{length(legacy)} legacy providers to ReqLLM...")
          Adapter.migrate_old_config()
          load_providers_from_req_llm()
        else
          []
        end
      else
        providers
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
    Adapter.to_req_llm_provider(provider)
    :ets.insert(state.table, {provider.name, provider})
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
    notify_router()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) do
    :ets.delete(state.table, name)
    ProviderConfig.disable_provider(name)
    notify_router()
    {:reply, :ok, state}
  end

  # ── Provider Loading ───────────────────────────────────────

  defp load_providers_from_req_llm do
    LLMProvider.list_providers()
    |> Enum.map(&Adapter.to_provider_info/1)
    |> Enum.reject(&is_nil/1)
  rescue
    e ->
      Logger.error("Error loading providers from ReqLLM: #{inspect(e)}")
      []
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
