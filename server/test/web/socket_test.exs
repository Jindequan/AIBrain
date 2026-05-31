defmodule AIBrain.Web.SocketTest do
  use ExUnit.Case, async: false

  alias AIBrain.Web.Socket

  setup do
    case Process.whereis(AIBrain.Session.Store.Memory) do
      nil ->
        start_supervised!({AIBrain.Session.Store.Memory, [name: AIBrain.Session.Store.Memory]})

      _ ->
        :ok
    end

    :ok
  end

  test "heartbeat ping only returns pong" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}
    payload = Jason.encode!(%{type: "ping"})

    assert {:push, [{:text, response}], ^state} = Socket.handle_in({payload, []}, state)
    assert Jason.decode!(response) == %{"type" => "pong"}
  end

  test "ignores non-run payloads received on the run event channel" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}

    assert {:ok, ^state} = Socket.handle_info({:run_event, "run-1", :ping}, state)
  end

  test "pushes valid run events" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}
    event = %{type: :tool_start, tool_name: "browser", tool_use_id: "tool-1"}

    assert {:push, [{:text, response}], ^state} =
             Socket.handle_info({:run_event, "run-1", event}, state)

    assert %{
             "type" => "event",
             "event" => "run_event",
             "data" => %{
               "run_id" => "run-1",
               "tool_name" => "browser",
               "tool_use_id" => "tool-1",
               "status" => "started"
             }
           } = Jason.decode!(response)
  end

  test "session events include session id for frontend routing" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}
    event = %{type: :text_delta, text: "hello"}

    assert {:push, [{:text, response}], ^state} =
             Socket.handle_info({:session_event, "session-1", event}, state)

    assert %{
             "type" => "event",
             "event" => "text_delta",
             "session_id" => "session-1",
             "data" => %{
               "session_id" => "session-1",
               "text" => "hello"
             }
           } = Jason.decode!(response)
  end

  test "provider failure events expose public errors only" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}

    event = %{
      type: :provider_failed,
      provider_name: "openai",
      reason: {:provider_error, "HTTP 500: stack trace"}
    }

    assert {:push, [{:text, response}], ^state} =
             Socket.handle_info({:session_event, "session-1", event}, state)

    decoded = Jason.decode!(response)
    assert decoded["event"] == "provider_failed"
    assert decoded["data"]["provider_name"] == "openai"
    assert decoded["data"]["reason"] == "HTTP 500: stack trace"
  end

  test "rejects a query when the session is already running" do
    state = %{subscribed_sessions: MapSet.new(), subscribed_runs: MapSet.new()}
    session_id = "ws-running-#{System.unique_integer([:positive])}"
    pid = spawn(fn -> Process.sleep(:infinity) end)

    try do
      :ok = AIBrain.Session.Registry.register(session_id, pid)
      payload = Jason.encode!(%{session_id: session_id, message: "hello"})

      assert {:push, [{:text, response}], _new_state} = Socket.handle_in({payload, []}, state)
      decoded = Jason.decode!(response)
      assert decoded["type"] == "error"
      assert decoded["session_id"] == session_id
      assert decoded["error"] == "Session is currently running"
    after
      AIBrain.Session.Registry.unregister(session_id)
      Process.exit(pid, :kill)
    end
  end
end
