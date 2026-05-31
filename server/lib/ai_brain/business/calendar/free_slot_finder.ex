defmodule AIBrain.Business.Calendar.FreeSlotFinder do
  @moduledoc """
  Finds free time slots between busy periods.

  Takes a list of busy periods and searches for the first gap
  of at least `duration_minutes` length within the given time range.
  """

  @doc """
  Find the first free slot of `duration_minutes` length.

  Busy periods can be in either format:
  - `%{"start" => iso_string, "end" => iso_string}` (from ICS)
  - `%{"start" => %{"dateTime" => iso}, "end" => %{"dateTime" => iso}}` (from Google)

  Returns `{:ok, %{"free_slot" => %{"start" => iso, "end" => iso}}}` or
  `{:ok, %{"free_slot" => nil, "message" => "..."}}`.
  """
  def find(busy, time_min, time_max, duration_minutes) do
    sorted = Enum.sort_by(busy, fn b -> parse_busy_start(b) end, DateTime)
    gap_secs = duration_minutes * 60

    case find_gap(sorted, time_min, time_max, gap_secs) do
      {start_dt, end_dt} ->
        {:ok,
         %{
           "free_slot" => %{
             "start" => DateTime.to_iso8601(start_dt),
             "end" => DateTime.to_iso8601(end_dt)
           }
         }}

      nil ->
        {:ok,
         %{
           "free_slot" => nil,
           "message" => "No free #{duration_minutes}-minute slot found in range"
         }}
    end
  end

  # -- Gap Finding Algorithm --

  defp find_gap([], cursor, time_max, gap_secs) do
    if DateTime.diff(time_max, cursor) >= gap_secs do
      {cursor, DateTime.add(cursor, gap_secs, :second)}
    end
  end

  defp find_gap([busy | rest], cursor, time_max, gap_secs) do
    busy_start = parse_busy_start(busy)
    busy_end = parse_busy_end(busy)

    if DateTime.compare(cursor, busy_start) == :lt do
      gap = DateTime.diff(busy_start, cursor)

      if gap >= gap_secs do
        {cursor, DateTime.add(cursor, gap_secs, :second)}
      else
        new_cursor = if DateTime.compare(busy_end, cursor) == :gt, do: busy_end, else: cursor
        find_gap(rest, new_cursor, time_max, gap_secs)
      end
    else
      new_cursor = if DateTime.compare(busy_end, cursor) == :gt, do: busy_end, else: cursor
      find_gap(rest, new_cursor, time_max, gap_secs)
    end
  end

  # -- Busy Period Parsing --

  # Google format: %{"start" => %{"dateTime" => "..."}}
  defp parse_busy_start(%{"start" => %{"dateTime" => dt}}), do: parse_iso!(dt)
  # ICS format: %{"start" => "2025-01-15T10:00:00Z"}
  defp parse_busy_start(%{"start" => s}) when is_binary(s), do: parse_iso!(s)
  defp parse_busy_start(_), do: DateTime.utc_now()

  defp parse_busy_end(%{"end" => %{"dateTime" => dt}}), do: parse_iso!(dt)
  defp parse_busy_end(%{"end" => e}) when is_binary(e), do: parse_iso!(e)
  defp parse_busy_end(_), do: DateTime.utc_now() |> DateTime.add(3600, :second)

  defp parse_iso!(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
