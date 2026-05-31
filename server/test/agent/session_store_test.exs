defmodule AIBrain.Core.SessionStoreTest do
  use ExUnit.Case, async: true

  alias AIBrain.Core.Events
  alias AIBrain.Session.Store.Memory

  test "resume_messages/2 returns ordered messages" do
    {:ok, store} = Memory.start_link(name: nil)

    assert :ok =
             Memory.start_session(
               store,
               "s1",
               messages: [%{role: "user", content: "hello"}],
               requested_model: "claude-test"
             )

    assert :ok = Memory.append_event(store, "s1", Events.query_started(%{session_id: "s1"}))
    assert :ok = Memory.append_event(store, "s1", Events.text_delta("Hello"))
    assert :ok = Memory.append_event(store, "s1", Events.turn_complete("Hello", "end_turn"))

    assert [%{role: "user", content: "hello"}] = Memory.resume_messages(store, "s1")
  end

  test "resume_messages/2 returns the latest valid canonical messages" do
    {:ok, store} = Memory.start_link(name: nil)

    tool_call = %{type: "tool_use", id: "t1", name: "echo", input: %{"msg" => "hi"}}
    tool_result = %{type: "tool_result", tool_use_id: "t1", content: "ECHO: hi"}

    assert :ok =
             Memory.start_session(
               store,
               "resume-1",
               messages: [%{role: "user", content: "hi"}]
             )

    assert :ok =
             Memory.append_message(store, "resume-1", %{role: "assistant", content: [tool_call]})

    assert :ok = Memory.append_message(store, "resume-1", %{role: "user", content: [tool_result]})

    assert [
             %{role: "user", content: "hi"},
             %{role: "assistant", content: [^tool_call]},
             %{role: "user", content: [^tool_result]}
           ] = Memory.resume_messages(store, "resume-1")
  end

  describe "list_sessions/1" do
    test "returns empty list when no sessions" do
      {:ok, store} = Memory.start_link(name: nil)
      assert [] == Memory.list_sessions(store)
    end

    test "returns all started sessions" do
      {:ok, store} = Memory.start_link(name: nil)
      Memory.start_session(store, "s1", messages: [], requested_model: "m1", metadata: %{})
      Memory.start_session(store, "s2", messages: [], requested_model: "m2", metadata: %{})
      ids = store |> Memory.list_sessions() |> Enum.map(& &1.session_id) |> Enum.sort()
      assert ids == ["s1", "s2"]
    end

    test "session summary includes message_count" do
      {:ok, store} = Memory.start_link(name: nil)
      Memory.start_session(store, "s3", messages: [], requested_model: "m", metadata: %{})
      Memory.append_message(store, "s3", %{role: "user", content: "hi"})
      [summary] = Memory.list_sessions(store)
      assert summary.message_count == 1
    end

    test "session summary includes created_at" do
      {:ok, store} = Memory.start_link(name: nil)
      Memory.start_session(store, "s4", messages: [], requested_model: "m", metadata: %{})
      [summary] = Memory.list_sessions(store)
      assert is_binary(summary.created_at)
    end
  end

  test "concurrent sessions remain isolated by session_id" do
    {:ok, store} = Memory.start_link(name: nil)

    assert :ok = Memory.start_session(store, "s1", messages: [%{role: "user", content: "one"}])
    assert :ok = Memory.start_session(store, "s2", messages: [%{role: "user", content: "two"}])

    assert :ok = Memory.append_event(store, "s1", Events.text_delta("A"))
    assert :ok = Memory.append_event(store, "s2", Events.text_delta("B"))
    assert :ok = Memory.append_message(store, "s1", %{role: "assistant", content: "alpha"})
    assert :ok = Memory.append_message(store, "s2", %{role: "assistant", content: "beta"})

    assert [
             %{role: "user", content: "one"},
             %{role: "assistant", content: "alpha"}
           ] = Memory.resume_messages(store, "s1")

    assert [
             %{role: "user", content: "two"},
             %{role: "assistant", content: "beta"}
           ] = Memory.resume_messages(store, "s2")

    assert [%{role: "user", content: "one"}, %{role: "assistant", content: "alpha"}] =
             Memory.resume_messages(store, "s1")

    assert [%{role: "user", content: "two"}, %{role: "assistant", content: "beta"}] =
             Memory.resume_messages(store, "s2")
  end
end
