defmodule AIBrain.Telemetry.Metrics do
  @moduledoc """
  Thin wrapper around :telemetry for standardised AIBrain event emission.

  All events use the [:ai_brain, ...] prefix so reporters can attach
  to the whole tree or individual branches.
  """

  @prefix [:ai_brain]

  @doc """
  Time a function execution and emit start/stop events.

  Always emits `[:ai_brain, event..., :stop]` with `%{duration_ms: float}`.
  On exception, emits `[:ai_brain, event..., :exception]` and re-raises.
  """
  def span(event_suffix, metadata \\ %{}, fun) when is_function(fun, 0) do
    start = System.monotonic_time(:millisecond)

    try do
      fun.()
    catch
      kind, reason ->
        elapsed = System.monotonic_time(:millisecond) - start
        measure = %{duration_ms: elapsed}
        meta = Map.put(metadata, :error, inspect(reason))
        emit(event_suffix ++ [:exception], measure, meta)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        elapsed = System.monotonic_time(:millisecond) - start
        emit(event_suffix ++ [:stop], %{duration_ms: elapsed}, metadata)

        case result do
          {:ok, _, _} ->
            emit(event_suffix ++ [:success], %{duration_ms: elapsed}, metadata)

          {:error, _} ->
            emit(event_suffix ++ [:failure], %{duration_ms: elapsed}, metadata)

          _ ->
            :ok
        end

        result
    end
  end

  @doc "Emit a single event with measurements and metadata."
  def emit(event_suffix, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(@prefix ++ event_suffix, measurements, metadata)
  end
end
