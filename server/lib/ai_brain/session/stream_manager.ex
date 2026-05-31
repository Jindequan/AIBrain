defmodule AIBrain.Session.StreamManager do
  @moduledoc """
  ETS-based streaming storage for messages.

  During streaming, chunks are stored in ETS for fast access.
  When streaming completes, chunks are merged and persisted to conversation.jsonl.
  """

  use GenServer
  require Logger

  @ets_table :stream_chunks
  @context_table :stream_context

  defstruct [:session_id, :message_id, :started_at, :chunk_count]

  # ==================== GenServer ====================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ==================== Client API ====================

  @doc "Start a new stream for a message"
  def start_stream(session_id, message_id) do
    GenServer.call(__MODULE__, {:start_stream, session_id, message_id}, 10_000)
  end

  @doc "Append a chunk to the stream (fire-and-forget)"
  def append_chunk(session_id, message_id, seq, type, data) do
    GenServer.cast(__MODULE__, {:append_chunk, session_id, message_id, seq, type, data})
  end

  @doc "Finish the stream and persist to conversation.jsonl"
  def finish_stream(session_id, message_id) do
    GenServer.call(__MODULE__, {:finish_stream, session_id, message_id}, 30_000)
  end

  @doc "Get current chunks for a message (for debugging)"
  def get_chunks(session_id, message_id) do
    :ets.tab2list(@ets_table)
    |> Enum.filter(fn {{sid, mid, _seq}, _val} -> sid == session_id and mid == message_id end)
    |> Enum.sort_by(fn {{_sid, _mid, seq}, _val} -> seq end)
    |> Enum.map(fn {{_sid, _mid, _seq}, val} -> val end)
  end

  # ==================== Server Callbacks ====================

  @impl true
  def init(_) do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@context_table, [:named_table, :set, :public])

    # Start periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_stream, session_id, message_id}, _from, state) do
    context = %__MODULE__{
      session_id: session_id,
      message_id: message_id,
      started_at: DateTime.utc_now(),
      chunk_count: 0
    }

    :ets.insert(@context_table, {message_id, context})

    {:reply, {:ok, message_id}, state}
  end

  @impl true
  def handle_call({:finish_stream, session_id, message_id}, _from, state) do
    case :ets.lookup(@context_table, message_id) do
      [{^message_id, context}] ->
        # CRITICAL: Collect chunks BEFORE any cleanup
        chunks =
          :ets.tab2list(@ets_table)
          |> Enum.filter(fn {{sid, mid, _seq}, _val} ->
            sid == session_id and mid == message_id
          end)
          |> Enum.sort_by(fn {{_sid, _mid, seq}, _val} -> seq end)
          |> Enum.map(fn {{_sid, _mid, _seq}, val} -> val end)

        # Delete chunks from ETS FIRST (prevent duplicate reads)
        :ets.tab2list(@ets_table)
        |> Enum.each(fn {{sid, mid, seq}, _val} ->
          if sid == context.session_id and mid == message_id do
            :ets.delete(@ets_table, {sid, mid, seq})
          end
        end)

        # Delete context
        :ets.delete(@context_table, message_id)

        # Synchronously persist to ensure chunks are saved
        persist_message(context, chunks)

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :stream_not_found}, state}
    end
  end

  @impl true
  def handle_cast({:append_chunk, session_id, message_id, seq, type, data}, state) do
    case :ets.lookup(@context_table, message_id) do
      [{^message_id, _context}] ->
        chunk = %{
          type: type,
          data: data,
          timestamp: DateTime.utc_now()
        }

        :ets.insert(@ets_table, {{session_id, message_id, seq}, chunk})
        {:noreply, state}

      [] ->
        Logger.warning("Stream not found for message_id=#{message_id}, dropping chunk")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_streams()

    # Prune stale EventBuffer sessions (TTL configurable, defaults to 1 hour)
    try do
      ttl = Application.get_env(:ai_brain, :event_buffer_ttl_seconds, 3600)
      AIBrain.Session.EventBuffer.cleanup_expired(ttl)
    rescue
      e -> Logger.warning("EventBuffer.cleanup_expired failed: #{Exception.message(e)}")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # ==================== Private Functions ====================

  defp persist_message(context, chunks) do
    try do
      # 1. Build message from chunks
      message = build_message_from_chunks(context.message_id, chunks)

      # 2. Append to conversation.jsonl (disk)
      # This is the PRIMARY write path
      AIBrain.ConversationLog.append_message(context.session_id, message)

      Logger.debug("Persisted message #{context.message_id} for session #{context.session_id}")
    rescue
      e ->
        Logger.error("Error persisting message: #{inspect(e)}")
    end
  end

  defp build_message_from_chunks(message_id, chunks) do
    content_parts =
      Enum.reduce(chunks, [], fn chunk, acc ->
        case chunk.type do
          :text_delta ->
            # Append to last text block if exists, otherwise create new
            if acc != [] and List.last(acc).type == "text" do
              List.update_at(acc, length(acc) - 1, fn p ->
                %{p | text: p.text <> chunk.data}
              end)
            else
              acc ++ [%{type: "text", text: chunk.data}]
            end

          :thinking_start ->
            acc ++
              [%{type: "thinking", thinking_index: chunk.data.index, text: ""}]

          :thinking_delta ->
            index = chunk.data.index
            # Find or create thinking block
            case Enum.find_index(acc, fn p ->
                   p.type == "thinking" and p.thinking_index == index
                 end) do
              nil ->
                acc ++ [%{type: "thinking", thinking_index: index, text: chunk.data}]

              idx ->
                List.update_at(acc, idx, fn p -> %{p | text: (p.text || "") <> chunk.data} end)
            end

          :tool_use_start ->
            acc ++
              [
                %{
                  type: "tool_use",
                  id: chunk.data.tool_use_id,
                  name: chunk.data.tool_name,
                  input: chunk.data.input,
                  output: nil,
                  status: "running"
                }
              ]

          :tool_result ->
            Enum.map(acc, fn
              %{type: "tool_use", id: id} = p when id == chunk.data.tool_use_id ->
                %{p | output: chunk.data.output, status: "success"}

              p ->
                p
            end)

          _ ->
            acc
        end
      end)

    %AIBrain.Message{
      id: message_id,
      role: "assistant",
      content: content_parts
    }
  end

  defp schedule_cleanup do
    # Cleanup every 5 minutes
    Process.send_after(self(), :cleanup, :timer.minutes(5))
  end

  defp cleanup_expired_streams do
    now = DateTime.utc_now()
    expiration = DateTime.add(now, -1, :hour)

    @context_table
    |> :ets.tab2list()
    |> Enum.each(fn {message_id, context} ->
      if DateTime.before?(context.started_at, expiration) do
        Logger.warning("Cleaning up expired stream: #{message_id}")

        # Clean up ETS
        :ets.delete(@context_table, message_id)

        # Delete all chunks for this message
        :ets.tab2list(@ets_table)
        |> Enum.each(fn {{sid, mid, seq}, _val} ->
          if sid == context.session_id and mid == message_id do
            :ets.delete(@ets_table, {sid, mid, seq})
          end
        end)
      end
    end)
  end
end
