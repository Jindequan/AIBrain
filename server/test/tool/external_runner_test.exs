defmodule AIBrain.Tool.ExternalRunnerTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.ExternalRunner

  test "runs a shell handler and returns stdout on exit 0" do
    handler = %{"type" => "shell", "path" => "echo", "action" => "hello"}
    {:ok, output} = ExternalRunner.run(handler, %{}, %{})
    assert output =~ "hello"
  end

  test "returns error on non-zero exit" do
    handler = %{"type" => "shell", "path" => "sh", "action" => "-c 'exit 1'"}
    {:error, msg} = ExternalRunner.run(handler, %{}, %{})
    assert msg =~ "exited"
  end

  test "returns error for unknown handler type" do
    handler = %{"type" => "unknown_type"}
    {:error, msg} = ExternalRunner.run(handler, %{}, %{})
    assert msg =~ "Unknown handler type"
  end
end
