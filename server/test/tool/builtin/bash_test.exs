defmodule AIBrain.Tool.Builtin.BashTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.{Builtin.Bash, Error}

  test "executes simple command and returns structured output" do
    assert {:ok, result} = Bash.execute(%{"command" => "echo hello"}, %{})
    assert String.trim(result.content) == "hello"
    assert result.metadata[:exit_code] == 0
    assert result.metadata[:command] == "echo hello"
  end

  test "returns structured error on failure" do
    assert {:error, %Error{category: :execution} = error} =
             Bash.execute(%{"command" => "ls nonexistent_path_xyz"}, %{})

    assert error.message =~ "No such file"
    assert error.details[:exit_code] != 0
  end

  test "respects timeout option" do
    result = Bash.execute(%{"command" => "sleep 60"}, %{timeout: 100})
    assert {:error, %Error{category: :timeout}} = result
  end

  test "executes in given working directory" do
    {:ok, cwd} = File.cwd()

    assert {:ok, result} = Bash.execute(%{"command" => "pwd"}, %{cwd: cwd})
    assert String.trim(result.content) == cwd
    assert result.metadata[:cwd] == cwd
  end

  test "blocks absolute path reads outside allowed roots" do
    assert {:error, {:sandbox_blocked, :workspace_read, message}} =
             Bash.execute(%{"command" => "cat /etc/hosts"}, %{})

    assert message =~ "outside the allowed workspace"
  end

  test "read_only? is false" do
    refute Bash.read_only?()
  end
end
