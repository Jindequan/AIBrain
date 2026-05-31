defmodule AIBrain.Memory.EnhancedManager do
  @moduledoc """
  Enhanced Memory Manager - clear cache orchestration, no task-dodging.

  ## Responsibility

  THIS MODULE owns caching and parallel store dispatch. It does NOT:
    - Interpret query results (just caches and returns)
    - Know what stores do internally (just calls their search/2)
    - Handle index logic (just schedules store refresh)

  ## Flow

  search(query_text, opts)
    → Query.build/2 (validate input)
    → 1) Check cache → hit → return cached Result
    → 2) Cache miss → parallel store search → fuse scores → cache → return computed Result
  """

  use GenServer
  require Logger

  @cache_max_size 100
  # 5 minutes
  @cache_ttl 300_000
  @parallel_timeout 5_000

  defstruct [
    # ETS table for query cache
    :cache,
    # monotonic counter
    :index_version,
    # monotonic time of last index refresh
    :last_refresh,
    # %{cache_hits, cache_misses, total_queries}
    :stats
  ]

  @type t :: %__MODULE__{
          cache: :ets.tid(),
          index_version: pos_integer(),
          last_refresh: non_neg_integer(),
          stats: %{
            cache_hits: non_neg_integer(),
            cache_misses: non_neg_integer(),
            total_queries: non_neg_integer()
          }
        }

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Search memory stores with caching.

  Returns `%Result{...}` on success, `{:error, reason}` on validation failure.
  """
  def search(query_text, opts \\ []) do
    query = AIBrain.Memory.Query.build(query_text, opts)

    case AIBrain.Memory.Query.validate(query) do
      :ok ->
        case GenServer.call(__MODULE__, {:search, query}, 10_000) do
          %AIBrain.Memory.Result{} = result -> result
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Invalidate cache and trigger index refresh."
  def refresh_cache do
    GenServer.cast(__MODULE__, :refresh_cache)
  end

  @doc "Notify that new entries were added."
  def notify_new_entries(entries) do
    GenServer.cast(__MODULE__, {:new_entries, entries})
  end

  @doc "Get cache statistics."
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # ── GenServer callbacks ──────────────────────────────────────

  @impl true
  def init(_opts) do
    cache = :ets.new(:memory_cache, [:set, :public, read_concurrency: true])
    schedule_refresh()

    state = %__MODULE__{
      cache: cache,
      index_version: 1,
      last_refresh: System.monotonic_time(:millisecond),
      stats: %{cache_hits: 0, cache_misses: 0, total_queries: 0}
    }

    Logger.info("EnhancedManager: started with cache and incremental indexing")
    {:ok, state}
  end

  @impl true
  def handle_call({:search, %AIBrain.Memory.Query{} = query}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    case lookup_cache(state.cache, query) do
      {:hit, entries} ->
        # Cache hit: wrap in cached Result, update stats, return
        result = AIBrain.Memory.Result.cached(entries, start_time)
        new_stats = bump_stats(state.stats, :cache_hit)
        {:reply, result, %{state | stats: new_stats}}

      {:miss, _cache_key} ->
        # Cache miss: search stores, cache result, return
        {result, new_state} = do_search_and_cache(query, state, start_time)
        new_stats = bump_stats(new_state.stats, :cache_miss)
        {:reply, result, %{new_state | stats: new_stats}}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total = state.stats.cache_hits + state.stats.cache_misses
    hit_rate = if total > 0, do: state.stats.cache_hits / total * 100, else: 0.0

    {:reply, Map.put(state.stats, :hit_rate_percent, hit_rate), state}
  end

  @impl true
  def handle_cast(:refresh_cache, state) do
    :ets.delete_all_objects(state.cache)
    new_version = state.index_version + 1
    Logger.info("EnhancedManager: cache refreshed (version #{new_version})")
    {:noreply, %{state | index_version: new_version}}
  end

  @impl true
  def handle_cast({:new_entries, entries}, state) do
    # Conservative: clear all cache on new entries
    if length(entries) > 0 do
      :ets.delete_all_objects(state.cache)
      Logger.debug("EnhancedManager: cache cleared (new entries)")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_index, state) do
    now = System.monotonic_time(:millisecond)

    if now - state.last_refresh >= @cache_ttl do
      spawn(fn -> refresh_store_indexes() end)
      schedule_refresh()
      {:noreply, %{state | last_refresh: now}}
    else
      {:noreply, state}
    end
  end

  # ── Cache operations ────────────────────────────────────────

  defp lookup_cache(cache, %AIBrain.Memory.Query{} = query) do
    cache_key = build_cache_key(query)

    case :ets.lookup(cache, cache_key) do
      [{^cache_key, entries, timestamp}] ->
        if fresh?(timestamp) do
          {:hit, entries}
        else
          :ets.delete(cache, cache_key)
          {:miss, cache_key}
        end

      [] ->
        {:miss, cache_key}
    end
  end

  defp fresh?(timestamp) do
    System.monotonic_time(:millisecond) - timestamp < @cache_ttl
  end

  defp build_cache_key(%AIBrain.Memory.Query{} = q) do
    {q.text, q.limit, q.sources, q.type, q.session_id}
  end

  defp write_cache(cache, cache_key, entries) do
    :ets.insert(cache, {cache_key, entries, System.monotonic_time(:millisecond)})
    enforce_cache_limit(cache)
  end

  defp enforce_cache_limit(cache) do
    size = :ets.info(cache, :size)

    if size > @cache_max_size do
      to_remove = size - @cache_max_size

      cache
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_, _, ts} -> ts end)
      |> Enum.take(to_remove)
      |> Enum.each(fn {k, _, _} -> :ets.delete(cache, k) end)
    end
  end

  # ── Search pipeline ─────────────────────────────────────────

  defp do_search_and_cache(query, state, start_time) do
    sources = query.sources || default_sources()

    entries =
      query
      |> dispatch_to_stores(sources)
      |> fuse_duplicate_results()
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(query.limit)

    result = AIBrain.Memory.Result.computed(entries, start_time)

    cache_key = build_cache_key(query)
    write_cache(state.cache, cache_key, entries)

    Logger.debug("EnhancedManager: #{result.elapsed_ms}ms / #{length(entries)} results")

    {result, state}
  end

  defp dispatch_to_stores(query, sources) do
    if parallel_enabled?() do
      sources
      |> Task.async_stream(
        fn store -> store.search(query.text, limit: query.limit) end,
        timeout: @parallel_timeout,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, entries} -> entries
        {:exit, _reason} -> []
      end)
    else
      Enum.flat_map(sources, &safe_store_search(&1, query))
    end
  end

  defp safe_store_search(store, query) do
    store.search(query.text, limit: query.limit)
  rescue
    e ->
      Logger.warning("EnhancedManager: #{inspect(store)} search failed: #{Exception.message(e)}")
      []
  end

  defp parallel_enabled? do
    Application.get_env(:ai_brain, :memory_parallelism, true)
  end

  # ── Score fusion ────────────────────────────────────────────

  defp fuse_duplicate_results(results) do
    results
    |> Enum.group_by(fn entry ->
      entry.content |> String.downcase() |> String.trim()
    end)
    |> Enum.map(fn {_normalized, group} ->
      best = Enum.max_by(group, fn e -> Map.get(e, :confidence, 0.0) end)

      best
      |> Map.put(:confidence, weighted_confidence(group))
      |> Map.put(:sources, Enum.map(group, & &1.source))
    end)
  end

  defp weighted_confidence(entries) do
    weights = %{
      knowledge_wiki: 0.40,
      rag: 0.30,
      session: 0.20,
      workspace: 0.10
    }

    {total_weight, sum} =
      Enum.reduce(entries, {0.0, 0.0}, fn e, {w_acc, s_acc} ->
        w = Map.get(weights, e.source, 0.1)
        {w_acc + w, s_acc + Map.get(e, :confidence, 0.0) * w}
      end)

    if total_weight > 0, do: sum / total_weight, else: 0.0
  end

  # ── Statistics ──────────────────────────────────────────────

  defp bump_stats(stats, :cache_hit) do
    %{stats | cache_hits: stats.cache_hits + 1, total_queries: stats.total_queries + 1}
  end

  defp bump_stats(stats, :cache_miss) do
    %{stats | cache_misses: stats.cache_misses + 1, total_queries: stats.total_queries + 1}
  end

  # ── Store helpers ──────────────────────────────────────────

  defp default_sources do
    [
      AIBrain.Memory.Stores.KnowledgeWiki,
      AIBrain.Memory.Stores.RAG,
      AIBrain.Memory.Stores.Session,
      AIBrain.Memory.Stores.Workspace
    ]
  end

  defp refresh_store_indexes do
    stores = [AIBrain.Memory.Stores.KnowledgeWiki, AIBrain.Memory.Stores.RAG]

    Enum.each(stores, fn store ->
      if function_exported?(store, :refresh_index, 0) do
        try do
          store.refresh_index()
        rescue
          e ->
            Logger.warning(
              "EnhancedManager: index refresh failed for #{inspect(store)}: #{Exception.message(e)}"
            )
        end
      end
    end)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_index, @cache_ttl)
  end
end
