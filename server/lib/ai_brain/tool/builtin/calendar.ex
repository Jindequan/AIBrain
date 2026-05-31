defmodule AIBrain.Tool.Builtin.Calendar do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Calendar tool — thin adapter that delegates all logic to Business.Calendar.

  This tool should ONLY contain:
  1. Tool.Behaviour callbacks (name, description, input_schema, etc.)
  2. Argument validation
  3. Delegation to the Business layer
  """

  alias AIBrain.Business.Calendar

  def name, do: "calendar"

  def description,
    do:
      "Manage calendar: list events, create, delete, find free slots. Supports Google Calendar, CalDAV (iCloud), and local .ics files."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["list_events", "create_event", "delete_event", "find_free_slot"],
          "description" => "Action to perform"
        },
        "days" => %{
          "type" => "integer",
          "description" => "Number of days to look ahead (default 7)"
        },
        "max_results" => %{"type" => "integer", "description" => "Max events (default 20)"},
        "summary" => %{"type" => "string", "description" => "Event title/summary"},
        "description" => %{"type" => "string", "description" => "Event description"},
        "location" => %{"type" => "string", "description" => "Event location"},
        "start" => %{
          "type" => "string",
          "description" => "Start datetime ISO 8601 (e.g. 2025-01-15T14:00:00)"
        },
        "end" => %{"type" => "string", "description" => "End datetime ISO 8601"},
        "event_id" => %{"type" => "string", "description" => "Event ID to delete"},
        "duration_minutes" => %{
          "type" => "integer",
          "description" => "Meeting duration in minutes (for find_free_slot, default 60)"
        },
        "time_min" => %{
          "type" => "string",
          "description" => "Search start ISO 8601 (for find_free_slot)"
        },
        "time_max" => %{
          "type" => "string",
          "description" => "Search end ISO 8601 (for find_free_slot)"
        }
      },
      "required" => ["action"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :network

  # -- Dispatch — thin delegation to Business layer --

  def execute(%{"action" => "list_events"} = args, _context) do
    Calendar.list_events(days: args["days"], max_results: args["max_results"])
  end

  def execute(%{"action" => "create_event"} = args, _context) do
    Calendar.create_event(
      summary: args["summary"],
      start: args["start"],
      end: args["end"],
      description: args["description"],
      location: args["location"]
    )
  end

  def execute(%{"action" => "delete_event"} = args, _context) do
    Calendar.delete_event(args["event_id"])
  end

  def execute(%{"action" => "find_free_slot"} = args, _context) do
    time_min = parse_iso(args["time_min"])
    time_max = parse_iso(args["time_max"])

    opts = [
      duration_minutes: args["duration_minutes"],
      days: args["days"]
    ]

    opts = if time_min, do: Keyword.put(opts, :time_min, time_min), else: opts
    opts = if time_max, do: Keyword.put(opts, :time_max, time_max), else: opts

    Calendar.find_free_slot(opts)
  end

  def execute(%{}, _),
    do: {:error, "Action must be: list_events, create_event, delete_event, find_free_slot"}

  defp parse_iso(nil), do: nil

  defp parse_iso(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
