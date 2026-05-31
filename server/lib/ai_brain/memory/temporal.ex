defmodule AIBrain.Memory.Temporal do
  @moduledoc """
  Temporal awareness for the memory system.

  Provides date/time context and recent event awareness so the agent
  knows "today is Saturday" and "you last worked on X 3 days ago".
  """

  import Ecto.Query
  alias AIBrain.Repo
  require Logger

  @doc """
  Returns a temporal context string for LLM prompt injection.
  """
  def build_context do
    now = DateTime.utc_now()
    time_str = now |> DateTime.to_time() |> Time.to_string()

    # Extract HH:MM from "HH:MM:SS" format safely
    time_parts = String.split(time_str, ":")
    hour_min = Enum.take(time_parts, 2) |> Enum.join(":")

    """
    **Today:** #{Date.to_string(now)} (#{day_name(now)})
    **Time:** #{hour_min}
    """
  end

  @doc """
  Find the last N sessions that interacted with the user.
  Returns their summaries and timestamps.
  """
  def recent_sessions(days \\ 7) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day) |> DateTime.to_iso8601()

    Repo.all(
      from(s in "sessions",
        where: s.notes != "" and s.inserted_at > ^cutoff,
        order_by: [desc: s.inserted_at],
        limit: 5,
        select: [:id, :notes, :inserted_at]
      )
    )
  rescue
    e ->
      Logger.warning("AIBrain.Memory.Temporal.recent_sessions failed: #{Exception.message(e)}")
      []
  end

  @doc """
  Find the most recent completed Run to know what was last done.
  """
  def last_action do
    Repo.one(
      from(r in AIBrain.Data.Run,
        where: r.status == "completed",
        order_by: [desc: r.completed_at],
        limit: 1,
        select: [:id, :completed_at]
      )
    )
  rescue
    e ->
      Logger.warning("AIBrain.Memory.Temporal.last_action failed: #{Exception.message(e)}")
      nil
  end

  @doc """
  Format recent activity for context injection.
  """
  def format_recent_activity do
    sessions = recent_sessions(7)
    last_run = last_action()

    if sessions == [] and last_run == nil do
      ""
    else
      parts = []

      parts =
        if last_run do
          elapsed = time_ago(last_run.completed_at)
          ["- **Last completed action:** #{last_run.id} (#{elapsed})" | parts]
        else
          parts
        end

      parts =
        if sessions != [] do
          session_lines =
            Enum.map(sessions, fn s ->
              elapsed = time_ago(s.inserted_at)
              note = String.slice(s.notes || "", 0, 100)
              "- #{elapsed}: #{note}"
            end)

          ["- **Recent sessions:**" | session_lines] ++ parts
        else
          parts
        end

      (["## Recent Activity", ""] ++ parts) |> Enum.join("\n")
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp day_name(dt) do
    case Date.day_of_week(dt) do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
    end
  end

  defp time_ago(nil), do: "unknown"

  defp time_ago(dt_str) when is_binary(dt_str) do
    case DateTime.from_iso8601(dt_str) do
      {:ok, dt, _} -> time_ago(dt)
      _ -> "unknown"
    end
  end

  defp time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :minute)

    cond do
      diff < 60 -> "#{diff} minutes ago"
      diff < 1440 -> "#{div(diff, 60)} hours ago"
      true -> "#{div(diff, 1440)} days ago"
    end
  end
end
