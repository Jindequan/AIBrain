defmodule AIBrain.Channel.Responders.SchedulerResponder do
  @moduledoc """
  Builds channel-friendly replies for scheduler queries.
  """

  alias AIBrain.Channel.Reply

  def build_status(diagnostics) do
    text = render_diagnostics(diagnostics)
    Reply.build(:scheduler_status, text)
  end

  def build_item_created(item) do
    text = "Scheduled #{item.type} item #{item.id}"

    text =
      if item.next_fire_at,
        do: text <> " (next fire: #{DateTime.to_iso8601(item.next_fire_at)})",
        else: text

    Reply.build(:scheduler_status, text, %{item_id: item.id})
  end

  defp render_diagnostics(%{counts: counts, upcoming: upcoming}) do
    lines = [
      "Scheduler Status:",
      "  Active: #{counts.active}, Paused: #{counts.paused}, Fired: #{counts.fired}, Cancelled: #{counts.cancelled}"
    ]

    upcoming_lines =
      case upcoming do
        [] ->
          ["  No upcoming items."]

        items ->
          [
            "  Upcoming:"
            | Enum.map(items, fn item ->
                "    - #{item.id}: #{item.type} at #{DateTime.to_iso8601(item.next_fire_at)}"
              end)
          ]
      end

    Enum.join(lines ++ upcoming_lines, "\n")
  end
end
