defmodule AIBrain.Session.EventBuffer do
  @moduledoc """
  Per-session event buffer for SSE event replay after frontend reconnection.

  Events are stored in ETS with auto-incrementing sequence numbers per session.
  When the frontend reconnects (after WebSocket disconnect or page refresh), it
  calls `GET /api/v1/sessions/:id/events?since=N` to replay events it missed.

  Cleanup:
  - `cleanup/1` — call explicitly when a session ends
  - `cleanup_expired/1` — prune stale sessions; schedule periodically via a GenServer or cron
  """

  require Logger

  @events_table :session_event_buffer
  @seqs_table :session_event_seqs

  @doc "Initialize ETS tables. Safe to call multiple times."
  def init_tables do
    if :ets.whereis(@events_table) == :undefined do
      :ets.new(@events_table, [:named_table, :set, :public, read_concurrency: true])
    end

    if :ets.whereis(@seqs_table) == :undefined do
      :ets.new(@seqs_table, [:named_table, :set, :public])
    end

    :ok
  end

  @doc """
  Append an event to the session's buffer. Returns the sequence number assigned.

  The event is stored regardless of whether the frontend is connected. The
  frontend fetches missed events on reconnect via `get_events_since/2`.
  """
  def append(session_id, event) do
    seq = :ets.update_counter(@seqs_table, session_id, {2, 1}, {session_id, 0})

    entry = %{
      seq: seq,
      event: event,
      timestamp: DateTime.utc_now()
    }

    :ets.insert(@events_table, {{session_id, seq}, entry})
    seq
  end

  @doc "Get all events since a given sequence number (exclusive). Defaults to 0."
  def get_events_since(session_id, since_seq \\ 0) do
    @events_table
    |> :ets.tab2list()
    |> Enum.filter(fn {{sid, seq}, _val} -> sid == session_id and seq > since_seq end)
    |> Enum.sort_by(fn {{_sid, seq}, _val} -> seq end)
    |> Enum.map(fn {_key, val} -> val end)
  end

  @doc "Get the latest sequence number for a session (0 if no events yet)."
  def latest_seq(session_id) do
    case :ets.lookup(@seqs_table, session_id) do
      [{^session_id, seq}] -> seq
      [] -> 0
    end
  end

  @doc "Clean up all events for a session. Called when session completes or is deleted."
  def cleanup(session_id) do
    :ets.delete(@seqs_table, session_id)

    @events_table
    |> :ets.tab2list()
    |> Enum.each(fn {{sid, _seq}, _val} = entry ->
      if sid == session_id, do: :ets.delete_object(@events_table, entry)
    end)

    :ok
  end

  @doc "Check if a session has buffered events."
  def has_events?(session_id) do
    @events_table
    |> :ets.tab2list()
    |> Enum.any?(fn {{sid, _seq}, _val} -> sid == session_id end)
  end

  @doc "Clean up expired sessions (older than TTL). Called periodically."
  def cleanup_expired(ttl_seconds \\ 3600) do
    cutoff = DateTime.utc_now() |> DateTime.add(-ttl_seconds, :second)

    @events_table
    |> :ets.tab2list()
    |> Enum.group_by(fn {{sid, _seq}, _val} -> sid end)
    |> Enum.each(fn {session_id, entries} ->
      {_key, newest_val} = Enum.max_by(entries, fn {{_sid, _seq}, val} -> val.timestamp end)

      if DateTime.before?(newest_val.timestamp, cutoff) do
        Logger.debug("EventBuffer: cleaning up expired session #{session_id}")
        cleanup(session_id)
      end
    end)
  end
end
