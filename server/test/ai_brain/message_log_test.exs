defmodule AIBrain.MessageLogTest do
  use ExUnit.Case, async: true

  alias AIBrain.MessageLog

  setup do
    dir = System.tmp_dir!() |> Path.join("message_log_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "messages.jsonl")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, path: path}
  end

  test "append writes a line and load reads it back", %{path: path} do
    msg = %{"role" => "user", "content" => "hello"}
    assert :ok = MessageLog.append(path, msg)

    assert {:ok, [loaded]} = MessageLog.load(path)
    assert loaded["role"] == "user"
    assert loaded["content"] == "hello"
    assert is_binary(loaded["ts"])
  end

  test "multiple appends preserve order", %{path: path} do
    for i <- 1..5 do
      MessageLog.append(path, %{"role" => "user", "content" => "msg #{i}"})
    end

    assert {:ok, msgs} = MessageLog.load(path)
    assert length(msgs) == 5
    assert Enum.map(msgs, & &1["content"]) == Enum.map(1..5, &"msg #{&1}")
  end

  test "load returns empty list for missing file", %{path: path} do
    assert {:ok, []} = MessageLog.load(path <> ".nonexistent")
  end

  test "load_up_to returns only first N messages", %{path: path} do
    for i <- 1..10 do
      MessageLog.append(path, %{"role" => "user", "content" => "msg #{i}"})
    end

    assert {:ok, msgs} = MessageLog.load_up_to(path, 3)
    assert length(msgs) == 3
    assert hd(msgs)["content"] == "msg 1"
  end

  test "append creates parent directory if missing" do
    path = System.tmp_dir!() |> Path.join("nested/deep/messages.jsonl")
    on_cleanup = fn -> File.rm_rf!(Path.join(System.tmp_dir!(), "nested")) end
    on_exit(on_cleanup)

    assert :ok = MessageLog.append(path, %{"role" => "user", "content" => "ok"})
    assert {:ok, [_]} = MessageLog.load(path)
  end

  test "load_up_to returns empty list for negative count", %{path: path} do
    MessageLog.append(path, %{"role" => "user", "content" => "hi"})
    assert {:ok, []} = MessageLog.load_up_to(path, -1)
  end

  test "messages_path/2 returns correct path" do
    Application.put_env(:ai_brain, :data_dir, "/tmp/test_dir")
    on_exit(fn -> Application.delete_env(:ai_brain, :data_dir) end)
    path = MessageLog.messages_path("runs", "run-123")
    assert path == "/tmp/test_dir/runs/run-123/messages.jsonl"
  end
end
