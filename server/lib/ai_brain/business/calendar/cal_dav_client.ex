defmodule AIBrain.Business.Calendar.CalDavClient do
  @moduledoc """
  CalDAV protocol client (iCloud, Nextcloud, Radicale, etc.).

  Supports listing, creating, and deleting events via CalDAV REPORT/PUT/DELETE.
  """

  require Logger
  require SweetXml
  import SweetXml, only: [sigil_x: 2]

  def list_events(days, max) do
    config = caldav_config()

    case validate_config(config) do
      :ok ->
        fetch_events(config, days, max)

      {:error, _} = err ->
        err
    end
  end

  def create_event(summary, start_iso, end_iso, desc, location) do
    config = caldav_config()

    case validate_config(config) do
      :ok ->
        put_event(config, summary, start_iso, end_iso, desc, location)

      {:error, _} = err ->
        err
    end
  end

  def delete_event(event_id) do
    config = caldav_config()

    case validate_config(config) do
      :ok ->
        do_delete(config, event_id)

      {:error, _} = err ->
        err
    end
  end

  # -- Implementation --

  defp fetch_events(config, days, max) do
    now = DateTime.utc_now()
    time_max = DateTime.add(now, days * 86400, :second)

    body = """
    <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
      <d:prop><d:getetag/><c:calendar-data/></d:prop>
      <c:filter>
        <c:comp-filter name="VCALENDAR">
          <c:comp-filter name="VEVENT">
            <c:time-range start="#{DateTime.to_iso8601(now)}" end="#{DateTime.to_iso8601(time_max)}"/>
          </c:comp-filter>
        </c:comp-filter>
      </c:filter>
    </c:calendar-query>
    """

    auth = basic_auth(config)

    case Req.request(
           method: :REPORT,
           url: config[:caldav_url],
           headers: [
             {"Authorization", "Basic #{auth}"},
             {"Content-Type", "application/xml; charset=UTF-8"},
             {"Depth", "1"}
           ],
           body: body
         ) do
      {:ok, %{status: 207, body: resp}} ->
        events = parse_multistatus(resp) |> Enum.take(max)
        {:ok, %{"events" => events, "count" => length(events)}}

      {:ok, %{status: s, body: b}} ->
        {:error, "CalDAV query failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "CalDAV error: #{inspect(reason)}"}
    end
  end

  defp put_event(config, summary, start_iso, end_iso, desc, location) do
    uid = UUID.uuid4()
    now_stamp = format_ics_datetime(DateTime.utc_now())
    start_ics = format_ics_datetime(start_iso)
    end_ics = format_ics_datetime(end_iso)
    desc_escaped = String.replace(desc, ~r{[\n\r]}, "\\n")
    loc_line = if location, do: "LOCATION:#{location}\n", else: ""

    ics = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//AIBrain//Calendar//EN
    BEGIN:VEVENT
    UID:#{uid}
    DTSTAMP:#{now_stamp}
    DTSTART:#{start_ics}
    DTEND:#{end_ics}
    SUMMARY:#{summary}
    #{loc_line}DESCRIPTION:#{desc_escaped}
    END:VEVENT
    END:VCALENDAR
    """

    auth = basic_auth(config)
    event_url = "#{String.trim_trailing(config[:caldav_url], "/")}/#{uid}.ics"

    case Req.put(event_url,
           headers: [
             {"Authorization", "Basic #{auth}"},
             {"Content-Type", "text/calendar; charset=UTF-8"}
           ],
           body: ics
         ) do
      {:ok, %{status: s}} when s in [201, 204] -> {:ok, "Event '#{summary}' created on CalDAV"}
      {:ok, %{status: s, body: b}} -> {:error, "CalDAV create failed HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, "CalDAV create error: #{inspect(reason)}"}
    end
  end

  defp do_delete(config, event_id) do
    auth = basic_auth(config)
    event_url = "#{String.trim_trailing(config[:caldav_url], "/")}/#{event_id}.ics"

    case Req.delete(event_url, headers: [{"Authorization", "Basic #{auth}"}]) do
      {:ok, %{status: s}} when s in [204, 200] ->
        {:ok, "Event deleted from CalDAV: #{event_id}"}

      {:ok, %{status: s, body: b}} ->
        {:error, "CalDAV delete failed HTTP #{s}: #{inspect(b)}"}

      {:error, reason} ->
        {:error, "CalDAV delete error: #{inspect(reason)}"}
    end
  end

  # -- XML Parsing --

  defp parse_multistatus(xml) when is_binary(xml) do
    case SweetXml.parse(xml) do
      {:ok, doc} ->
        doc
        |> SweetXml.xpath(~x"//c:calendar-data/text()"l)
        |> Enum.map(&AIBrain.Business.Calendar.IcsHandler.parse_event_block/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    e ->
      Logger.warning("CalDAV XML parse error: #{Exception.message(e)}")
      []
  end

  defp parse_multistatus(_), do: []

  # -- Helpers --

  defp validate_config(config) do
    if config[:caldav_url] && config[:caldav_username] && config[:caldav_password] do
      :ok
    else
      {:error,
       "CalDAV not configured. Set :caldav_url, :caldav_username, :caldav_password in config :ai_brain, :calendar"}
    end
  end

  defp basic_auth(config),
    do: Base.encode64("#{config[:caldav_username]}:#{config[:caldav_password]}")

  defp format_ics_datetime(iso_str) when is_binary(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _} -> format_ics_datetime(dt)
      _ -> iso_str
    end
  end

  defp format_ics_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.replace(~r{[:.-]}, "")
    |> Kernel.<>("Z")
  end

  defp caldav_config, do: AIBrain.Business.Calendar.config()
end
