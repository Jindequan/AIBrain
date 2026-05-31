defmodule AIBrain.Tool.ExecutorTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.{Executor, Registry, Error, Result}

  defmodule SlowReadTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "slow_read"
    def description, do: "slow read"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: true

    def execute(%{"delay" => ms}, _ctx) do
      Process.sleep(ms)
      {:ok, "read done in #{ms}ms"}
    end
  end

  defmodule FastWriteTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "fast_write"
    def description, do: "write"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: false
    def execute(%{"val" => v}, _ctx), do: {:ok, "wrote #{v}"}
  end

  defmodule CrashingTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "crasher"
    def description, do: "always crashes"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: true
    def execute(_args, _ctx), do: raise("boom")
  end

  defmodule ErrorTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "error_tool"
    def description, do: "returns error"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: true
    def execute(_args, _ctx), do: {:error, "something failed"}
  end

  defmodule BigOutputTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "big_output"
    def description, do: "big"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: true

    def execute(%{"size" => size}, _ctx) do
      {:ok, String.duplicate("x", size)}
    end
  end

  defmodule SummarizeTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "summarizer"
    def description, do: "has custom summarize"
    def input_schema, do: %{type: "object", properties: %{}}
    def read_only?, do: true

    def execute(_args, _ctx), do: {:ok, String.duplicate("line\n", 5_000)}

    def summarize(_output, _opts), do: "CUSTOM_SUMMARY"
  end

  setup do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, SlowReadTool)
    Registry.register(reg, FastWriteTool)
    Registry.register(reg, CrashingTool)
    Registry.register(reg, ErrorTool)
    Registry.register(reg, BigOutputTool)
    Registry.register(reg, SummarizeTool)
    {:ok, exec} = Executor.start_link(registry: reg)
    {:ok, exec: exec}
  end

  test "runs read-only tools in parallel", %{exec: exec} do
    tool_uses = [
      %{id: "t1", name: "slow_read", input: %{"delay" => 100}},
      %{id: "t2", name: "slow_read", input: %{"delay" => 100}}
    ]

    t0 = System.monotonic_time(:millisecond)
    results = Executor.run(exec, tool_uses, %{})
    elapsed = System.monotonic_time(:millisecond) - t0

    assert length(results) == 2
    assert elapsed < 180, "Expected parallel execution, took #{elapsed}ms"
  end

  test "runs write tools serially", %{exec: exec} do
    tool_uses = [
      %{id: "w1", name: "fast_write", input: %{"val" => "a"}},
      %{id: "w2", name: "fast_write", input: %{"val" => "b"}}
    ]

    results = Executor.run(exec, tool_uses, %{})
    assert length(results) == 2
  end

  test "returns Tool.Error for unknown tool", %{exec: exec} do
    [{_id, result}] = Executor.run(exec, [%{id: "x1", name: "unknown", input: %{}}], %{})
    assert {:error, %Error{category: :execution}} = result
  end

  test "wraps successful output in Tool.Result", %{exec: exec} do
    [{_id, result}] =
      Executor.run(exec, [%{id: "t1", name: "slow_read", input: %{"delay" => 0}}], %{})

    assert {:ok, %Result{content: "read done in 0ms", truncated: false}} = result
  end

  test "wraps string error in Tool.Error with :execution category", %{exec: exec} do
    [{_id, result}] = Executor.run(exec, [%{id: "e1", name: "error_tool", input: %{}}], %{})
    assert {:error, %Error{category: :execution, message: "something failed"}} = result
  end

  test "wraps crash in Tool.Error with :execution category", %{exec: exec} do
    [{_id, result}] = Executor.run(exec, [%{id: "c1", name: "crasher", input: %{}}], %{})
    assert {:error, %Error{category: :execution}} = result
    assert result |> elem(1) |> Map.get(:message) =~ "boom"
  end

  test "truncates large output and sets truncated flag", %{exec: exec} do
    [{_id, result}] =
      Executor.run(exec, [%{id: "b1", name: "big_output", input: %{"size" => 50_000}}], %{})

    assert {:ok, %Result{truncated: true}} = result
    assert result |> elem(1) |> Map.get(:byte_size) > 10_000
  end

  test "uses tool custom summarize when available", %{exec: exec} do
    [{_id, result}] = Executor.run(exec, [%{id: "s1", name: "summarizer", input: %{}}], %{})
    assert {:ok, %Result{truncated: true, content: "CUSTOM_SUMMARY"}} = result
  end

  test "writes full output to file_store when truncated", %{exec: exec} do
    dir = Path.join(System.tmp_dir!(), "executor_file_store_test_#{:rand.uniform(100_000)}")
    on_exit(fn -> File.rm_rf!(dir) end)

    [{_id, result}] =
      Executor.run(exec, [%{id: "b2", name: "big_output", input: %{"size" => 50_000}}], %{
        file_store: dir,
        tool_use_id: "b2"
      })

    assert {:ok, %Result{truncated: true, file_path: path}} = result
    assert path != nil
    assert File.exists?(path)
    assert byte_size(File.read!(path)) == 50_000
  end

  test "file_path is nil when no file_store in context", %{exec: exec} do
    [{_id, result}] =
      Executor.run(exec, [%{id: "b3", name: "big_output", input: %{"size" => 50_000}}], %{})

    assert {:ok, %Result{truncated: true, file_path: nil}} = result
  end

  describe "Tool.Result constructors" do
    test "ok/1 creates success result with content" do
      result = Result.ok("test output")
      assert result.success == true
      assert result.content == "test output"
      assert result.error_category == nil
      assert result.byte_size == 11
    end

    test "ok/2 creates result with metadata merged" do
      result = Result.ok("test", %{"query" => "search term", "count" => 5})
      assert result.success == true
      assert result.metadata["query"] == "search term"
      assert result.metadata["count"] == 5
    end

    test "error/3 creates failed result with category" do
      result = Result.error("not found", "external_service", %{"url" => "http://example.com"})
      assert result.success == false
      assert result.error_category == "external_service"
      assert result.content == "not found"
      assert result.metadata["url"] == "http://example.com"
    end
  end

  test "extracts metadata from structured tool return with content and metadata", %{exec: exec} do
    [{_id, result}] =
      Executor.run(exec, [%{id: "s1", name: "summarizer", input: %{}}], %{})

    assert {:ok, %Result{metadata: meta}} = result
    assert meta["tool_name"] == "summarizer"
  end

  test "handles backward-compatible string return", %{exec: exec} do
    [{_id, result}] =
      Executor.run(exec, [%{id: "t1", name: "slow_read", input: %{"delay" => 0}}], %{})

    assert {:ok, %Result{content: "read done in 0ms", metadata: %{"tool_name" => "slow_read"}}} =
             result
  end
end
