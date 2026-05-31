defmodule AIBrain.Tool.Sandbox.MacOSSandboxTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Sandbox.MacOSSandbox

  describe "available?/0" do
    test "returns boolean" do
      result = MacOSSandbox.available?()
      assert is_boolean(result)
    end
  end

  describe "macos?/0" do
    test "returns boolean" do
      result = MacOSSandbox.macos?()
      assert is_boolean(result)
    end
  end

  describe "run/2" do
    test "executes a simple command and returns output" do
      # sandbox-exec availability depends on the host; skip if not macOS
      if MacOSSandbox.available?() do
        {:ok, output} = MacOSSandbox.run("echo hello", cd: System.tmp_dir!())
        assert String.contains?(output, "hello")
      else
        # Not on macOS or sandbox-exec unavailable, test is skipped
        :ok
      end
    end
  end
end
