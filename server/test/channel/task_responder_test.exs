defmodule AIBrain.Channel.Responders.TaskResponderTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Responders.TaskResponder

  describe "build_status/1" do
    test "renders task status" do
      task = %{id: "task-1", status: "completed", description: "test task"}
      reply = TaskResponder.build_status(task)
      assert reply.content =~ "task-1"
      assert reply.content =~ "completed"
      assert reply.metadata.task_id == "task-1"
    end
  end

  describe "build_list/1" do
    test "renders task list" do
      tasks = [
        %{id: "task-1", status: "running", description: "running task"},
        %{id: "task-2", status: "completed", description: "done task"}
      ]

      reply = TaskResponder.build_list(tasks)
      assert reply.content =~ "2 total"
      assert reply.content =~ "task-1"
      assert reply.content =~ "task-2"
    end
  end

  describe "build_output/2" do
    test "renders task output" do
      task = %{id: "task-1", status: "completed"}
      reply = TaskResponder.build_output(task, "hello world output")
      assert reply.content =~ "hello world output"
    end

    test "truncates large output" do
      task = %{id: "task-1", status: "completed"}
      large_output = String.duplicate("x", 5000)
      reply = TaskResponder.build_output(task, large_output)
      assert byte_size(reply.content) < 5000
    end
  end
end
