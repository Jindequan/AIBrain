defmodule AIBrain.Business.Calendar do
  @moduledoc """
  Unified calendar business layer.

  Provides a single entry point for calendar operations, automatically
  routing to the correct backend (Google Calendar, CalDAV, or .ics files)
  based on configuration.

  The Tool layer should call these functions — never call backend clients directly.
  """

  alias AIBrain.Business.Calendar.{GoogleClient, CalDavClient, IcsHandler, FreeSlotFinder}

  # -- Public API --

  def list_events(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    max = Keyword.get(opts, :max_results, 20)

    case detect_backend() do
      :google -> GoogleClient.list_events(days, max)
      :caldav -> CalDavClient.list_events(days, max)
      :ics -> IcsHandler.list_events(days, max)
      nil -> {:error, "No calendar backend configured"}
    end
  end

  def create_event(opts) do
    summary = Keyword.get(opts, :summary, "Untitled Event")
    start_time = Keyword.get(opts, :start)
    end_time = Keyword.get(opts, :end)
    desc = Keyword.get(opts, :description, "")
    location = Keyword.get(opts, :location)

    if !start_time || !end_time do
      {:error, "Both 'start' and 'end' (ISO 8601) are required for create_event"}
    else
      case detect_backend() do
        :google -> GoogleClient.create_event(summary, start_time, end_time, desc, location)
        :caldav -> CalDavClient.create_event(summary, start_time, end_time, desc, location)
        :ics -> IcsHandler.create_event(summary, start_time, end_time, desc)
        nil -> {:error, "No calendar backend configured"}
      end
    end
  end

  def delete_event(event_id) do
    if !event_id do
      {:error, "Missing required: event_id"}
    else
      case detect_backend() do
        :google -> GoogleClient.delete_event(event_id)
        :caldav -> CalDavClient.delete_event(event_id)
        :ics -> IcsHandler.delete_event(event_id)
        nil -> {:error, "No calendar backend configured"}
      end
    end
  end

  def find_free_slot(opts \\ []) do
    duration = Keyword.get(opts, :duration_minutes) || 60
    days = Keyword.get(opts, :days) || 7
    time_min = Keyword.get(opts, :time_min) || DateTime.utc_now()
    time_max = Keyword.get(opts, :time_max) || DateTime.add(time_min, days * 86400, :second)

    case detect_backend() do
      :google ->
        case GoogleClient.fetch_busy_periods(time_min, time_max) do
          {:ok, busy} -> FreeSlotFinder.find(busy, time_min, time_max, duration)
          error -> error
        end

      :ics ->
        case IcsHandler.fetch_busy_periods(time_min, time_max) do
          {:ok, busy} -> FreeSlotFinder.find(busy, time_min, time_max, duration)
          error -> error
        end

      :caldav ->
        {:error, "find_free_slot is not supported with CalDAV backend (use Google or .ics)"}

      nil ->
        {:error, "No calendar backend configured"}
    end
  end

  # -- Backend Detection --

  def detect_backend do
    cond do
      configured?(:google_token) -> :google
      configured?(:caldav_url) -> :caldav
      configured?(:ics_path) -> :ics
      true -> nil
    end
  end

  defp configured?(key),
    do: Map.has_key?(config(), key) and config()[key] != nil

  def config, do: Application.get_env(:ai_brain, :calendar, %{})
  def get_token, do: config()[:google_token]
end
