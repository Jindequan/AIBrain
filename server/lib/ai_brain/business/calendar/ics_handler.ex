defmodule AIBrain.Business.Calendar.IcsHandler do
  @moduledoc """
  Local .ics file handler.

  Reads, parses, creates, and deletes events in iCalendar (.ics) files.
  Also provides busy period extraction for free slot finding.
  """

  def list_events(days, max) do
    case get_path() do
      {:ok, path} ->
        case File.read(path) do
          {:ok, content} ->
            now = DateTime.utc_now()
            cutoff = DateTime.add(now, days * 86400, :second)

            events =
              content
              |> String.split("BEGIN:VEVENT")
              |> Enum.drop(1)
              |> Enum.map(&parse_v_event(&1, now, cutoff))
              |> Enum.reject(&is_nil/1)
              |> Enum.sort_by(fn e -> e["start"] || "" end)
              |> Enum.take(max)

            {:ok, %{"events" => events, "count" => length(events)}}

          {:error, reason} ->
            {:error, "Failed to read calendar: #{:file.format_error(reason)}"}
        end

      {:error, _} = err ->
        err
    end
  end

  def create_event(summary, start_iso, end_iso, description) do
    case get_path() do
      {:ok, path} ->
        uid = UUID.uuid4()
        now_stamp = format_ics_datetime(DateTime.utc_now())
        start_ics = format_ics_datetime(start_iso)
        end_ics = format_ics_datetime(end_iso)
        desc_escaped = String.replace(description, ~r{[\n\r]}, "\\n")

        event_block = """
        BEGIN:VEVENT
        UID:#{uid}
        DTSTAMP:#{now_stamp}
        DTSTART:#{start_ics}
        DTEND:#{end_ics}
        SUMMARY:#{summary}
        DESCRIPTION:#{desc_escaped}
        END:VEVENT
        """

        case File.stat(path) do
          {:ok, _} ->
            content = File.read!(path)
            updated = String.replace(content, "END:VCALENDAR", "#{event_block}\nEND:VCALENDAR")
            File.write!(path, updated)

          {:error, _} ->
            File.write!(path, """
            BEGIN:VCALENDAR
            VERSION:2.0
            PRODID:-//AIBrain//Calendar//EN
            #{event_block}
            END:VCALENDAR
            """)
        end

        {:ok, "Event '#{summary}' added to calendar"}

      {:error, _} = err ->
        err
    end
  rescue
    e -> {:error, "Failed to create event: #{Exception.message(e)}"}
  end

  def delete_event(event_id) do
    case get_path() do
      {:ok, path} ->
        if File.exists?(path) do
          content = File.read!(path)
          pattern = ~r{BEGIN:VEVENT.*?UID:#{Regex.escape(event_id)}.*?END:VEVENT}s
          updated = Regex.replace(pattern, content, "")
          updated = Regex.replace(~r{\n\n\n+}, updated, "\n\n")
          File.write!(path, updated)
          {:ok, "Event #{event_id} removed from calendar"}
        else
          {:error, "Calendar file not found"}
        end

      {:error, _} = err ->
        err
    end
  rescue
    e -> {:error, "Failed to delete event: #{Exception.message(e)}"}
  end

  @doc """
  Extract busy periods from .ics file for free slot calculation.
  Returns `{:ok, [%{"start" => iso, "end" => iso}]}`.
  """
  def fetch_busy_periods(_time_min, _time_max) do
    case get_path() do
      {:ok, path} ->
        if File.exists?(path) do
          case File.read(path) do
            {:ok, content} ->
              busy =
                content
                |> String.split("BEGIN:VEVENT")
                |> Enum.drop(1)
                |> Enum.map(&parse_v_event_busy/1)
                |> Enum.reject(&is_nil/1)

              {:ok, busy}

            {:error, reason} ->
              {:error, "Failed to read calendar: #{:file.format_error(reason)}"}
          end
        else
          {:error, "No .ics file configured"}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Parse a single VEVENT block from CalDAV response or .ics content.
  Returns a formatted event map or nil.
  """
  def parse_event_block(ics) when is_binary(ics) do
    parts = String.split(ics, "BEGIN:VEVENT")

    if length(parts) < 2 do
      nil
    else
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, 365 * 86400, :second)
      parse_v_event(List.last(parts), now, cutoff)
    end
  end

  def parse_event_block(_), do: nil

  # -- Internal --

  defp parse_v_event(block, now, cutoff) do
    start_str = extract_field(block, "DTSTART")
    end_str = extract_field(block, "DTEND")
    summary = extract_field(block, "SUMMARY") || "(no title)"
    uid = extract_field(block, "UID")
    desc = extract_field(block, "DESCRIPTION") || ""

    with {:ok, start_dt} <- parse_ics_datetime(start_str),
         {:ok, end_dt} <- parse_ics_datetime(end_str) do
      if DateTime.compare(start_dt, cutoff) != :gt && DateTime.compare(start_dt, now) != :lt do
        %{
          "id" => uid,
          "summary" => summary,
          "start" => DateTime.to_iso8601(start_dt),
          "end" => DateTime.to_iso8601(end_dt),
          "description" => desc
        }
      end
    else
      _ -> nil
    end
  end

  defp parse_v_event_busy(block) do
    start_str = extract_field(block, "DTSTART")
    end_str = extract_field(block, "DTEND")

    with {:ok, start_dt} <- parse_ics_datetime(start_str),
         {:ok, end_dt} <- parse_ics_datetime(end_str) do
      %{"start" => DateTime.to_iso8601(start_dt), "end" => DateTime.to_iso8601(end_dt)}
    else
      _ -> nil
    end
  end

  defp extract_field(block, field) do
    case Regex.run(~r{^#{field}(?:;.*?)?:(.+)$}m, block, capture: :all_but_first) do
      [val] -> String.trim(val)
      _ -> nil
    end
  end

  defp parse_ics_datetime(nil), do: {:error, :no_date}

  defp parse_ics_datetime(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, dt, _} ->
        {:ok, dt}

      _ ->
        cleaned = String.replace(dt, ~r{[TZ]}, "")

        case Date.from_iso8601(cleaned) do
          {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
          _ -> {:error, :invalid_date}
        end
    end
  end

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

  defp get_path do
    path = AIBrain.Business.Calendar.config()[:ics_path]

    cond do
      path && File.exists?(path) -> {:ok, path}
      path -> {:error, "No calendar file found at #{path}"}
      true -> {:error, "No .ics file configured"}
    end
  end
end
