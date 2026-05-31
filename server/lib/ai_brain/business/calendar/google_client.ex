defmodule AIBrain.Business.Calendar.GoogleClient do
  @moduledoc """
  Google Calendar API client.

  Handles list, create, delete, and freebusy queries against
  the Google Calendar v3 API.
  """

  @google_api "https://www.googleapis.com/calendar/v3"

  def list_events(days, max) do
    token = get_token()
    calendar_id = get_calendar_id()

    now = DateTime.utc_now()
    time_max = DateTime.add(now, days * 86400, :second)

    case Req.get("#{@google_api}/calendars/#{calendar_id}/events",
           headers: auth_headers(token),
           params: %{
             timeMin: DateTime.to_iso8601(now),
             timeMax: DateTime.to_iso8601(time_max),
             maxResults: max,
             singleEvents: true,
             orderBy: "startTime"
           }
         ) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        events = Enum.map(items || [], &format_event/1)
        {:ok, %{"events" => events, "count" => length(events)}}

      {:ok, %{status: s, body: b}} ->
        {:error, "Google Calendar list failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "Google Calendar error: #{inspect(reason)}"}
    end
  end

  def create_event(summary, start_iso, end_iso, desc, location) do
    token = get_token()
    calendar_id = get_calendar_id()

    event = %{
      summary: summary,
      start: %{dateTime: start_iso},
      end: %{dateTime: end_iso}
    }

    event = if desc != "", do: Map.put(event, :description, desc), else: event
    event = if location, do: Map.put(event, :location, location), else: event

    case Req.post("#{@google_api}/calendars/#{calendar_id}/events",
           headers: auth_headers(token) ++ [{"Content-Type", "application/json"}],
           json: event
         ) do
      {:ok, %{status: 200, body: evt}} ->
        {:ok, "Event '#{summary}' created: #{evt["htmlLink"] || evt["id"]}"}

      {:ok, %{status: s, body: b}} ->
        {:error, "Google Calendar create failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "Google Calendar create error: #{inspect(reason)}"}
    end
  end

  def delete_event(event_id) do
    token = get_token()
    calendar_id = get_calendar_id()

    case Req.delete("#{@google_api}/calendars/#{calendar_id}/events/#{event_id}",
           headers: auth_headers(token)
         ) do
      {:ok, %{status: 204}} ->
        {:ok, "Event deleted: #{event_id}"}

      {:ok, %{status: s, body: b}} ->
        {:error, "Google Calendar delete failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "Google Calendar delete error: #{inspect(reason)}"}
    end
  end

  def fetch_busy_periods(time_min, time_max) do
    token = get_token()
    calendar_id = get_calendar_id()

    case Req.post("#{@google_api}/calendars/#{calendar_id}/freeBusy",
           headers: auth_headers(token) ++ [{"Content-Type", "application/json"}],
           json: %{
             timeMin: DateTime.to_iso8601(time_min),
             timeMax: DateTime.to_iso8601(time_max),
             items: [%{id: calendar_id}]
           }
         ) do
      {:ok, %{status: 200, body: %{"calendars" => %{^calendar_id => %{"busy" => busy}}}}} ->
        {:ok, busy}

      {:ok, %{status: s, body: b}} ->
        {:error, "Google freeBusy failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "Google freeBusy error: #{inspect(reason)}"}
    end
  end

  # -- Helpers --

  defp format_event(evt) do
    start_info = evt["start"] || %{}
    end_info = evt["end"] || %{}

    %{
      "id" => evt["id"],
      "summary" => evt["summary"] || "(no title)",
      "start" => start_info["dateTime"] || start_info["date"],
      "end" => end_info["dateTime"] || end_info["date"],
      "location" => evt["location"],
      "description" => evt["description"] || "",
      "link" => evt["htmlLink"]
    }
  end

  defp auth_headers(token),
    do: [{"Authorization", "Bearer #{token}"}]

  defp get_token, do: AIBrain.Business.Calendar.config()[:google_token]
  defp get_calendar_id, do: AIBrain.Business.Calendar.config()[:google_calendar_id] || "primary"
end
