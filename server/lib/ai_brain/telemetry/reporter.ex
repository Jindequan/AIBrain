defmodule AIBrain.Telemetry.Reporter do
  @moduledoc """
  Attaches to [:ai_brain, ...] telemetry events and persists span data.

  Maintains an in-memory ETS ring buffer for recent spans and persists
  completed spans to a telemetry_spans SQLite table.

  Provides query functions for metrics dashboards.
  """

  use GenServer
  require Logger

  @ets_table :ai_brain_telemetry_spans
  @max_ets_rows 1000

  # ── Public API ──────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return recent spans from the ETS ring buffer."
  def recent_spans(limit \\ 100) do
    :ets.tab2list(@ets_table)
    |> Enum.sort_by(fn {ts, _, _, _} -> ts end, :desc)
    |> Enum.take(limit)
  end

  @doc "Query spans from the SQLite store."
  def query_spans(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    event_type = Keyword.get(opts, :event)
    min_duration = Keyword.get(opts, :min_duration_ms)

    if not persist_enabled?() do
      recent_spans(limit)
      |> Enum.map(&span_from_ets/1)
      |> Enum.filter(&span_matches?(&1, event_type, min_duration))
    else
      query_persisted_spans(limit, event_type, min_duration)
    end
  rescue
    e ->
      Logger.error("Telemetry.Reporter.query_spans failed: #{Exception.message(e)}")
      []
  end

  defp query_persisted_spans(limit, event_type, min_duration) do
    {where, params} = build_span_query(event_type, min_duration)

    sql = """
    SELECT id, event, measurements, metadata, inserted_at
    FROM telemetry_spans
    #{where}
    ORDER BY inserted_at DESC
    LIMIT ?
    """

    params = params ++ [limit]

    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)

    Enum.map(result.rows, fn [id, event, measurements_json, metadata_json, inserted_at] ->
      %{
        id: id,
        event: event,
        measurements: decode_json(measurements_json),
        metadata: decode_json(metadata_json),
        inserted_at: inserted_at
      }
    end)
  end

  @doc "Return aggregate metrics for the dashboard."
  def aggregate_metrics do
    %{
      llm_calls: count_by_event("llm.call.stop"),
      llm_errors: count_by_event("llm.call.exception"),
      avg_llm_latency_ms: avg_duration("llm.call.stop"),
      p95_llm_latency_ms: percentile_duration("llm.call.stop", 0.95),
      tool_calls: count_by_event("tool.execute.stop"),
      tool_errors: count_by_event("tool.execute.exception"),
      avg_tool_latency_ms: avg_duration("tool.execute.stop"),
      queries: count_by_event("query.stop"),
      query_failures: count_by_event("query.failure"),
      avg_query_duration_ms: avg_duration("query.stop"),
      router_selections: count_by_event("router.select.stop")
    }
  end

  @doc false
  def handle_event(name, measurements, metadata, _config) do
    send(__MODULE__, {:telemetry_span, name, measurements, metadata})
  end

  # ── Callbacks ───────────────────────────────────────────────────

  def init(_opts) do
    :ets.new(@ets_table, [:named_table, :public, :ordered_set])

    :ok = attach_handlers()

    Logger.info("Telemetry.Reporter: attached to [:ai_brain, ...] events")

    {:ok, %{ets_pos: 0}}
  end

  def handle_info({:telemetry_span, event, measurements, metadata}, state) do
    span_id = "#{Enum.join(event, ".")}-#{System.unique_integer([:positive])}"
    now = System.system_time(:millisecond)

    # Store in ETS ring buffer
    :ets.insert(@ets_table, {now, event, measurements, metadata})
    trim_ets()

    persist_span(span_id, event, measurements, metadata)

    {:noreply, state}
  end

  # ── Persistence ─────────────────────────────────────────────────

  defp persist_span(_id, event, measurements, metadata) do
    if not persist_enabled?(), do: throw(:telemetry_persist_disabled)

    event_str = Enum.join(event, ".")
    measurements_json = Jason.encode!(measurements)
    metadata_json = Jason.encode!(safe_metadata(metadata))
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      """
      INSERT INTO telemetry_spans (event, measurements, metadata, inserted_at)
      VALUES (?, ?, ?, ?)
      """,
      [event_str, measurements_json, metadata_json, now]
    )
  rescue
    e ->
      Logger.error("Telemetry.Reporter.persist_span failed: #{Exception.message(e)}")
      :ok
  catch
    :telemetry_persist_disabled -> :ok
  end

  defp safe_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {k, v} ->
      {to_string(k), safe_value(v)}
    end)
  end

  defp safe_metadata(_), do: %{}

  defp safe_value(value) when is_atom(value), do: to_string(value)

  defp safe_value(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Map.new(value, fn {k, v} -> {to_string(k), safe_value(v)} end)
    else
      Enum.map(value, &safe_value/1)
    end
  end

  defp safe_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> safe_value()

  defp safe_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {to_string(k), safe_value(v)} end)
  end

  defp safe_value(value), do: value

  # ── ETS management ──────────────────────────────────────────────

  defp trim_ets do
    count = :ets.info(@ets_table, :size)

    if count > @max_ets_rows do
      # Delete oldest entries
      keys_to_delete =
        :ets.tab2list(@ets_table)
        |> Enum.take(count - @max_ets_rows)
        |> Enum.map(fn {ts, _, _, _} -> ts end)

      Enum.each(keys_to_delete, &:ets.delete(@ets_table, &1))
    end
  end

  # ── Telemetry attachment ────────────────────────────────────────

  defp attach_handlers do
    events = [
      [:ai_brain, :llm, :call, :stop],
      [:ai_brain, :llm, :call, :exception],
      [:ai_brain, :llm, :error],
      [:ai_brain, :loop, :turn, :stop],
      [:ai_brain, :loop, :turn, :exception],
      [:ai_brain, :loop, :retry],
      [:ai_brain, :query, :stop],
      [:ai_brain, :query, :success],
      [:ai_brain, :query, :failure],
      [:ai_brain, :query, :exception],
      [:ai_brain, :router, :select, :stop],
      [:ai_brain, :tool, :execute, :stop],
      [:ai_brain, :tool, :execute, :exception]
    ]

    Enum.each(events, fn event ->
      handler_id = String.to_atom("ai_brain_reporter_#{Enum.join(event, "_")}")

      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_event/4,
        nil
      )
    end)

    :ok
  end

  # ── Aggregate queries ───────────────────────────────────────────

  defp count_by_event(event_name) do
    if not persist_enabled?() do
      recent_spans(@max_ets_rows)
      |> Enum.count(fn span ->
        span
        |> span_from_ets()
        |> span_matches?(event_name, nil)
      end)
    else
      count_persisted_event(event_name)
    end
  end

  defp count_persisted_event(event_name) do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT COUNT(*) FROM telemetry_spans WHERE event = ? AND inserted_at > ?",
        [event_name, one_hour_ago()]
      )

    case result.rows do
      [[count]] -> count
      _ -> 0
    end
  rescue
    e ->
      Logger.warning("Telemetry.Reporter: count_by_event failed: #{Exception.message(e)}")
      0
  end

  defp avg_duration(event_name) do
    if not persist_enabled?() do
      event_name
      |> ets_durations()
      |> average_duration()
    else
      avg_persisted_duration(event_name)
    end
  end

  defp avg_persisted_duration(event_name) do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        """
        SELECT AVG(CAST(json_extract(measurements, '$.duration_ms') AS REAL))
        FROM telemetry_spans
        WHERE event = ? AND inserted_at > ?
        """,
        [event_name, one_hour_ago()]
      )

    case result.rows do
      [[nil]] -> 0.0
      [[avg]] -> Float.round(avg, 2)
      _ -> 0.0
    end
  rescue
    e ->
      Logger.warning("Telemetry.Reporter: avg_duration failed: #{Exception.message(e)}")
      0.0
  end

  defp percentile_duration(event_name, percentile) do
    if not persist_enabled?() do
      event_name
      |> ets_durations()
      |> Enum.sort()
      |> percentile_value(percentile)
    else
      percentile_persisted_duration(event_name, percentile)
    end
  end

  defp percentile_persisted_duration(event_name, percentile) do
    # Approximate using ordered durations
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        """
        SELECT CAST(json_extract(measurements, '$.duration_ms') AS REAL)
        FROM telemetry_spans
        WHERE event = ? AND inserted_at > ?
        ORDER BY CAST(json_extract(measurements, '$.duration_ms') AS REAL)
        """,
        [event_name, one_hour_ago()]
      )

    durations = Enum.map(result.rows, fn [d] -> d || 0.0 end)
    if durations == [], do: 0.0, else: percentile_value(durations, percentile)
  rescue
    e ->
      Logger.warning("Telemetry.Reporter: percentile_duration failed: #{Exception.message(e)}")
      0.0
  end

  defp percentile_value([], _p), do: 0.0

  defp percentile_value(sorted, p) do
    idx = round(p * (length(sorted) - 1))
    # Use 0.0 as safe default instead of List.last(sorted) which returns nil for empty lists
    Enum.at(sorted, idx, 0.0)
  end

  defp one_hour_ago do
    DateTime.utc_now()
    |> DateTime.add(-3600, :second)
    |> DateTime.to_iso8601()
  end

  defp build_span_query(nil, nil), do: {"", []}
  defp build_span_query(event, nil) when is_binary(event), do: {"WHERE event = ?", [event]}

  defp build_span_query(nil, min_dur) when is_number(min_dur) do
    {"WHERE CAST(json_extract(measurements, '$.duration_ms') AS REAL) >= ?", [min_dur]}
  end

  defp build_span_query(event, min_dur) when is_binary(event) and is_number(min_dur) do
    {"WHERE event = ? AND CAST(json_extract(measurements, '$.duration_ms') AS REAL) >= ?",
     [event, min_dur]}
  end

  defp decode_json(nil), do: %{}

  defp decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp decode_json(_), do: %{}

  defp persist_enabled? do
    Application.get_env(:ai_brain, :telemetry_persist_enabled, true)
  end

  defp span_from_ets({ts, event, measurements, metadata}) do
    %{
      id: "#{Enum.join(event, ".")}-#{ts}",
      event: Enum.join(event, "."),
      measurements: safe_metadata(measurements),
      metadata: safe_metadata(metadata),
      inserted_at: DateTime.from_unix!(ts, :millisecond) |> DateTime.to_iso8601()
    }
  end

  defp span_matches?(span, event_type, min_duration) do
    event_match? = is_nil(event_type) or span.event == event_type

    duration_match? =
      is_nil(min_duration) or
        get_duration_ms(span.measurements) >= min_duration

    event_match? and duration_match?
  end

  defp ets_durations(event_name) do
    recent_spans(@max_ets_rows)
    |> Enum.map(&span_from_ets/1)
    |> Enum.filter(&span_matches?(&1, event_name, nil))
    |> Enum.map(fn span -> get_duration_ms(span.measurements) end)
  end

  defp average_duration([]), do: 0.0

  defp average_duration(durations) do
    durations
    |> Enum.sum()
    |> Kernel./(length(durations))
    |> Float.round(2)
  end

  defp get_duration_ms(measurements) when is_map(measurements) do
    Map.get(measurements, "duration_ms") ||
      Map.get(measurements, :duration_ms) ||
      0.0
  end

  defp get_duration_ms(_), do: 0.0
end
