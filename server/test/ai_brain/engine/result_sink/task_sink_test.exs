defmodule AIBrain.Engine.ResultSink.TaskSinkTest do
  use ExUnit.Case, async: true

  alias AIBrain.Engine.ResultSink.TaskSink
  alias AIBrain.MessageLog

  setup do
    task_id = "task-test-#{System.unique_integer([:positive])}"

    data_dir =
      System.tmp_dir!() |> Path.join("task_sink_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:ai_brain, :data_dir)
    end)

    {:ok, task_id: task_id, data_dir: data_dir}
  end

  test "save_message appends to tasks/<id>/messages.jsonl", %{task_id: id, data_dir: dir} do
    msg = %{"role" => "assistant", "content" => "result"}
    assert :ok = TaskSink.save_message(id, msg)

    path = Path.join([dir, "tasks", id, "messages.jsonl"])
    assert {:ok, [loaded]} = MessageLog.load(path)
    assert loaded["role"] == "assistant"
  end

  test "save_result returns :ok", %{task_id: id} do
    assert :ok = TaskSink.save_result(id, {:ok, "done", []})
    assert :ok = TaskSink.save_result(id, {:error, :timeout})
  end
end
