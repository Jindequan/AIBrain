defmodule AIBrain.Memory.Result do
  @moduledoc """
  Memory search result - explicit structure, NO guessing.

  Replaces unclear tuple returns like {:ok, :computed, results}.
  """

  defstruct [
    :entries,
    :source,
    :cache_status,
    :confidence,
    :elapsed_ms
  ]

  @type t :: %__MODULE__{
          entries: list(map()),
          source: atom(),
          cache_status: :cached | :computed,
          confidence: float(),
          elapsed_ms: non_neg_integer()
        }

  @type cache_status :: :cached | :computed

  @doc """
  Create result from search.
  """
  def create(entries, source, cache_status, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    # Calculate average confidence
    confidence =
      if length(entries) > 0 do
        entries
        |> Enum.map(fn e -> Map.get(e, :confidence, 0.0) end)
        |> Enum.sum()
        |> Kernel./(length(entries))
      else
        0.0
      end

    %__MODULE__{
      entries: entries,
      source: source,
      cache_status: cache_status,
      confidence: confidence,
      elapsed_ms: elapsed
    }
  end

  @doc """
  Create cached result (data came from cache, not freshly computed).
  """
  def cached(entries, start_time) do
    create(entries, :cache, :cached, start_time)
  end

  @doc """
  Create computed result (freshly computed from stores).
  """
  def computed(entries, start_time) do
    create(entries, :computed, :computed, start_time)
  end

  @doc """
  Convert to legacy format for backward compatibility.
  """
  def to_legacy_format(%__MODULE__{} = result) do
    {:ok, result.cache_status, result.entries}
  end
end
