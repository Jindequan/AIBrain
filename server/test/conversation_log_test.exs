defmodule AIBrain.ConversationLogTest do
  use ExUnit.Case, async: false

  alias AIBrain.ConversationLog

  setup do
    data_dir =
      System.tmp_dir!() |> Path.join("conv_log_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:ai_brain, :data_dir)
    end)

    :ok
  end

  test "append_message stores and loads a single message" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"

    msg = %{"role" => "user", "content" => [%{"type" => "text", "text" => "hello"}]}
    assert :ok = ConversationLog.append_message(session_id, msg)

    assert {:ok, messages, _meta} = ConversationLog.load_conversation(session_id)
    assert length(messages) == 1
    assert hd(messages).role == "user"
  end

  test "append_messages stores multiple messages as JSONL lines" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"

    messages = [
      %{"role" => "user", "content" => [%{"type" => "text", "text" => "run tool"}]},
      %{
        "role" => "assistant",
        "content" => [
          %{"type" => "tool_use", "id" => "t1", "name" => "echo", "input" => %{"msg" => "hi"}}
        ]
      }
    ]

    assert :ok = ConversationLog.append_messages(session_id, messages)
    assert {:ok, loaded, _meta} = ConversationLog.load_conversation(session_id)
    assert length(loaded) == 2
    assert ["user", "assistant"] = Enum.map(loaded, & &1.role)
  end

  test "append_message starts a new JSONL row when existing file has no trailing newline" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"
    path = ConversationLog.log_file_path(session_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"role" => "user", "content" => "first"}))

    assert :ok =
             ConversationLog.append_message(session_id, %{
               "role" => "assistant",
               "content" => "second"
             })

    assert {:ok, messages, _meta} = ConversationLog.load_conversation(session_id)
    assert Enum.map(messages, & &1.role) == ["user", "assistant"]
    assert File.read!(path) |> String.split("\n", trim: true) |> length() == 2
  end

  test "append_messages starts a new JSONL row when existing file has no trailing newline" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"
    path = ConversationLog.log_file_path(session_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"role" => "user", "content" => "first"}))

    assert :ok =
             ConversationLog.append_messages(session_id, [
               %{"role" => "assistant", "content" => "second"},
               %{"role" => "user", "content" => "third"}
             ])

    assert {:ok, messages, _meta} = ConversationLog.load_conversation(session_id)
    assert Enum.map(messages, & &1.role) == ["user", "assistant", "user"]
    assert File.read!(path) |> String.split("\n", trim: true) |> length() == 3
  end

  test "save_messages replaces all messages" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"

    ConversationLog.append_message(session_id, %{"role" => "user", "content" => "old"})
    ConversationLog.save_messages(session_id, [%{"role" => "user", "content" => "new"}])

    assert {:ok, messages, _meta} = ConversationLog.load_conversation(session_id)
    assert length(messages) == 1
    assert hd(messages).role == "user"
  end

  test "base_context persists across operations" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"

    ConversationLog.append_message(session_id, %{"role" => "user", "content" => "hi"})
    ConversationLog.set_base_context(session_id, "Previous conversation summary")

    assert {:ok, "Previous conversation summary"} = ConversationLog.get_base_context(session_id)
  end

  test "load_conversation returns not_found for non-existent session" do
    assert {:error, :not_found} = ConversationLog.load_conversation("nonexistent-session")
  end

  test "large tool results are externalized" do
    session_id = "conv-log-test-#{System.unique_integer([:positive])}"

    large_output = String.duplicate("x", 10_000)

    messages = [
      %{
        "role" => "assistant",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "t1",
            "name" => "bash",
            "input" => %{},
            "output" => large_output
          }
        ]
      }
    ]

    ConversationLog.append_messages(session_id, messages)

    # The JSONL line should have output_ref instead of inline output
    log_path = ConversationLog.log_file_path(session_id)
    [line] = File.read!(log_path) |> String.split("\n", trim: true)
    parsed = Jason.decode!(line)

    tool_block = hd(parsed["content"])
    assert tool_block["output_ref"] != nil
    assert tool_block["output"] == nil

    # But load_conversation should restore it
    assert {:ok, loaded, _meta} = ConversationLog.load_conversation(session_id)
    [restored_block] = hd(loaded).content
    assert restored_block["output"] == large_output
  end
end
