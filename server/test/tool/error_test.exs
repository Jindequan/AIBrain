defmodule AIBrain.Tool.ErrorTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Error

  describe "constructors" do
    test "permission creates error with :permission category" do
      err = Error.permission("sandbox blocked")
      assert %Error{category: :permission, message: "sandbox blocked"} = err
    end

    test "invalid_params creates error with :invalid_params category" do
      err = Error.invalid_params("missing field: path")
      assert %Error{category: :invalid_params, message: "missing field: path"} = err
    end

    test "execution creates error with :execution category" do
      err = Error.execution("crash")
      assert %Error{category: :execution, message: "crash"} = err
    end

    test "external_service creates error with :external_service category" do
      err = Error.external_service("API timeout")
      assert %Error{category: :external_service} = err
    end

    test "timeout creates error with :timeout category and details" do
      err = Error.timeout("timed out", tool_timeout: 5000, command: "ls")
      assert %Error{category: :timeout, details: %{tool_timeout: 5000, command: "ls"}} = err
    end

    test "unavailable creates error with :unavailable category" do
      err = Error.unavailable("xclip not found")
      assert %Error{category: :unavailable, message: "xclip not found"} = err
    end
  end

  describe "from/1 — wrapping existing errors" do
    test "passes through existing Tool.Error unchanged" do
      original = Error.permission("denied")
      assert Error.from(original) == original
    end

    test "wraps binary string as :execution" do
      err = Error.from("something went wrong")
      assert %Error{category: :execution, message: "something went wrong"} = err
    end

    test "wraps {:tool_crash, reason} as :execution" do
      err = Error.from({:tool_crash, "segfault"})
      assert %Error{category: :execution} = err
      assert err.message =~ "crashed"
    end

    test "wraps {:tool_exit, reason} as :execution" do
      err = Error.from({:tool_exit, :normal})
      assert %Error{category: :execution} = err
      assert err.message =~ "exited"
    end

    test "wraps {:tool_throw, reason} as :execution" do
      err = Error.from({:tool_throw, "oops"})
      assert %Error{category: :execution} = err
      assert err.message =~ "threw"
    end

    test "wraps unknown terms as :execution via inspect" do
      err = Error.from({:something_else, 42})
      assert %Error{category: :execution} = err
    end
  end
end
