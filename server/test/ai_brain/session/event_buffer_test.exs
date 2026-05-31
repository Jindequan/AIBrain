defmodule AIBrain.Session.EventBufferTest do
  use ExUnit.Case, async: false

  alias AIBrain.Session.EventBuffer

  setup do
    # Clean up tables between tests
    [:session_event_buffer, :session_event_seqs]
    |> Enum.each(fn t ->
      if :ets.whereis(t) != :undefined, do: :ets.delete(t)
    end)

    :ok
  end

  test "init_tables/0 creates ETS tables" do
    EventBuffer.init_tables()
    assert :ets.whereis(:session_event_buffer) != :undefined
    assert :ets.whereis(:session_event_seqs) != :undefined
  end

  test "init_tables/0 is idempotent — safe to call twice" do
    EventBuffer.init_tables()
    assert :ok == EventBuffer.init_tables()
  end

  test "append/2 stores event with incrementing sequence" do
    EventBuffer.init_tables()
    session_id = "sess-#{System.unique_integer([:positive])}"

    seq1 = EventBuffer.append(session_id, %{type: :text_delta, text: "hi"})
    seq2 = EventBuffer.append(session_id, %{type: :text_delta, text: "there"})

    assert seq1 == 1
    assert seq2 == 2
  end

  test "get_events_since/2 returns events after given seq" do
    EventBuffer.init_tables()
    session_id = "sess-#{System.unique_integer([:positive])}"

    EventBuffer.append(session_id, %{type: :a})
    EventBuffer.append(session_id, %{type: :b})
    EventBuffer.append(session_id, %{type: :c})

    events = EventBuffer.get_events_since(session_id, 1)
    assert length(events) == 2
    assert Enum.map(events, & &1.event.type) == [:b, :c]
  end

  test "latest_seq/1 returns 0 for unknown session" do
    EventBuffer.init_tables()
    assert EventBuffer.latest_seq("nonexistent-session") == 0
  end

  test "cleanup/1 removes all events for a session" do
    EventBuffer.init_tables()
    session_id = "sess-#{System.unique_integer([:positive])}"

    EventBuffer.append(session_id, %{type: :x})
    EventBuffer.cleanup(session_id)

    assert EventBuffer.get_events_since(session_id, 0) == []
    assert EventBuffer.latest_seq(session_id) == 0
  end

  describe "Channel.Bus integration" do
    test "publish/3 buffers event in EventBuffer" do
      EventBuffer.init_tables()
      {:ok, bus} = start_supervised({AIBrain.Channel.Bus, name: nil})

      session_id = "sess-#{System.unique_integer([:positive])}"
      event = %{type: :tool_result, tool_name: "bash", output: "ok"}

      AIBrain.Channel.Bus.publish(bus, session_id, event)

      events = EventBuffer.get_events_since(session_id, 0)
      assert length(events) == 1
      assert hd(events).event == event
    end
  end
end
