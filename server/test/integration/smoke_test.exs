defmodule AIBrain.SmokeTest do
  use AIBrain.DataCase, async: false
  import Mox

  @moduletag timeout: 120_000
  @moduletag :integration_smoke

  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Data.{RunContextRefs, Runs, RunSteps}
  alias AIBrain.Provider.{Info, Router}
  alias AIBrain.Session.Store.Memory
  alias AIBrain.Tool.{Registry, Executor}
  alias AIBrain.Tool.Builtin.{Bash, FileRead, FileWrite, FileEdit, Glob, Grep}

  setup :verify_on_exit!

  setup do
    data_dir =
      System.tmp_dir!() |> Path.join("smoke_runtime_#{System.unique_integer([:positive])}")

    File.mkdir_p!(data_dir)
    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:ai_brain, :data_dir)
    end)

    :ok
  end

  defmodule EchoTool do
    @behaviour AIBrain.Tool.Behaviour

    def name, do: "echo"
    def description, do: "echoes the input"
    def input_schema, do: %{type: "object", properties: %{msg: %{type: "string"}}}
    def read_only?, do: true
    def execute(%{"msg" => msg}, _ctx), do: {:ok, "echo:#{msg}"}
  end

  defmodule UpperTool do
    @behaviour AIBrain.Tool.Behaviour

    def name, do: "upper"
    def description, do: "uppercases the input"
    def input_schema, do: %{type: "object", properties: %{msg: %{type: "string"}}}
    def read_only?, do: true
    def execute(%{"msg" => msg}, _ctx), do: {:ok, String.upcase(msg)}
  end

  defp make_provider(name, priority) do
    %Info{
      name: name,
      api_key: "key-#{name}",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: priority
    }
  end

  defp start_executor_with_tools(tools) do
    {:ok, reg} = Registry.start_link(name: :"smoke_reg_#{System.unique_integer([:positive])}")
    Enum.each(tools, &Registry.register(reg, &1))
    {:ok, exec} = Executor.start_link(registry: reg)
    {reg, exec}
  end

  test "all builtin tools report correct read_only?" do
    {:ok, reg} = Registry.start_link(name: :"smoke_reg_#{System.unique_integer([:positive])}")
    Enum.each([Bash, FileRead, FileWrite, FileEdit, Glob, Grep], &Registry.register(reg, &1))

    assert Registry.read_only?(reg, "file_read")
    assert Registry.read_only?(reg, "glob")
    assert Registry.read_only?(reg, "grep")
    refute Registry.read_only?(reg, "bash")
    refute Registry.read_only?(reg, "file_write")
    refute Registry.read_only?(reg, "file_edit")
  end

  test "executor runs bash and file tools end-to-end" do
    {:ok, reg} = Registry.start_link(name: :"smoke_reg_#{System.unique_integer([:positive])}")
    Enum.each([Bash, FileRead, FileWrite], &Registry.register(reg, &1))
    {:ok, exec} = Executor.start_link(registry: reg)

    dir =
      Application.fetch_env!(:ai_brain, :data_dir)
      |> Path.join("workspace_#{:rand.uniform(99999)}")

    File.mkdir_p!(dir)
    file = Path.join(dir, "test.txt")

    write_results =
      Executor.run(
        exec,
        [
          %{id: "w1", name: "file_write", input: %{"path" => file, "content" => "hello smoke"}}
        ],
        %{}
      )

    read_results =
      Executor.run(
        exec,
        [
          %{id: "r1", name: "file_read", input: %{"path" => file}}
        ],
        %{}
      )

    assert {"w1", {:ok, _}} = Enum.find(write_results, fn {id, _} -> id == "w1" end)
    assert {"r1", {:ok, content}} = Enum.find(read_results, fn {id, _} -> id == "r1" end)
    text = if is_binary(content), do: content, else: Map.get(content, "content", inspect(content))
    assert String.contains?(text, "hello smoke")

    File.rm_rf(dir)
  end

  test "Agent.SSE.Parser.collect_sse_events handles multi-delta tool input" do
    events = [
      {:tool_use_start, %{index: 0, id: "u1", name: "bash"}},
      {:tool_input_delta, %{index: 0, chunk: "{\"command"}},
      {:tool_input_delta, %{index: 0, chunk: "\":\"echo hi\"}"}},
      {:content_block_stop, 0},
      {:stop, "tool_use"}
    ]

    result = AIBrain.LLM.SSE.Parser.collect_sse_events(events)
    assert result.stop_reason == :tool_call
    [tool] = result.tool_uses
    assert tool.name == "bash"
    assert tool.input == %{"command" => "echo hi"}
  end

  test "Agent.Loop smoke: failover retries same turn on 429 and second provider completes" do
    provider1 = make_provider("p1", 1)
    provider2 = make_provider("p2", 2)
    {:ok, router} = Router.start_link(providers: [provider1, provider2], name: nil)
    {_reg, exec} = start_executor_with_tools([])

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, _opts ->
      {:ok, %Req.Response{status: 429, headers: [{"retry-after", "30"}], body: %{}}}
    end)
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"content\":\"failover ok\"},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, %Req.Response{status: 200, headers: [], body: ""}}
    end)

    assert {:ok, "failover ok", _messages} =
             Orchestrator.run_messages(
               [%{role: "user", content: "hello"}],
               router: router,
               executor: exec,
               tools: [],
               http_client: AIBrain.LLM.HTTPMock
             )
  end

  test "P0/P1: session conversation creates a traceable unified run" do
    provider = make_provider("p1", 1)
    {:ok, router} = Router.start_link(providers: [provider], name: nil)
    {_reg, exec} = start_executor_with_tools([])
    {:ok, store} = Memory.start_link(name: nil)

    :ok =
      Memory.start_session(store, "session-p0", messages: [%{role: "user", content: "hello"}])

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"content\":\"tracked ok\"},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, %Req.Response{status: 200, headers: [], body: ""}}
    end)

    assert {:ok, %{run_id: run_id, result: {:ok, "tracked ok", _history}}} =
             Orchestrator.resume_session_with_run("session-p0",
               session_store: store,
               router: router,
               executor: exec,
               tools: [],
               mode: "interactive",
               http_client: AIBrain.LLM.HTTPMock
             )

    assert {:ok, run} = Runs.get_run(run_id)
    assert run.source_type == "chat"
    assert run.source_id == "session-p0"
    assert run.status == "completed"
    assert run.phase == "completed"
    assert run.output_summary == "tracked ok"

    refs = RunContextRefs.list_for_run(run_id)
    assert Enum.any?(refs, &(&1.ref_type == "session" and &1.ref_id == "session-p0"))
    assert Enum.any?(refs, &(&1.ref_type == "thread" and &1.ref_id == "session-p0"))

    assert Enum.any?(RunSteps.list_for_run(run_id), &(&1.title == "Agent transaction"))

    # Simple direct-response runs store output inline
    assert {:ok, run} = Runs.get_run(run_id)
    assert run.output == "tracked ok"

    assert {:ok, session} = Memory.load_session(store, "session-p0")
    assert Enum.any?(session.messages, &(&1.role == "assistant"))
  end

  test "chat run sends persisted session history without duplicating current user message" do
    provider = make_provider("p1", 1)
    {:ok, router} = Router.start_link(providers: [provider], name: nil)
    {_reg, exec} = start_executor_with_tools([])
    {:ok, store} = Memory.start_link(name: nil)

    session_id = "session-history-#{System.unique_integer([:positive])}"

    :ok = Memory.start_session(store, session_id, messages: [])

    :ok = AIBrain.ConversationLog.append_message(session_id, %{role: "user", content: "first"})

    :ok =
      AIBrain.ConversationLog.append_message(session_id, %{role: "assistant", content: "answer"})

    :ok =
      AIBrain.ConversationLog.append_message(session_id, %{role: "user", content: "follow up"})

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      api_messages = opts[:json]["messages"]
      non_system = Enum.reject(api_messages, &(Map.get(&1, :role) == "system"))

      assert Enum.map(non_system, &Map.get(&1, :role)) == ["user", "assistant", "user"]
      assert Enum.map(non_system, &Map.get(&1, :content)) == ["first", "answer", "follow up"]

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"content\":\"context ok\"},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, %Req.Response{status: 200, headers: [], body: ""}}
    end)

    assert {:ok, "context ok", _messages} =
             Orchestrator.run_messages(
               [%{role: "user", content: "follow up"}],
               session_id: session_id,
               router: router,
               executor: exec,
               session_store: store,
               tools: [],
               http_client: AIBrain.LLM.HTTPMock
             )
  end

  test "Agent.Loop smoke: two tool calls in one response both execute before final turn" do
    provider = make_provider("p1", 1)
    {:ok, router} = Router.start_link(providers: [provider], name: nil)
    {reg, exec} = start_executor_with_tools([EchoTool, UpperTool])
    test_pid = self()

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"t1\",\"function\":{\"name\":\"echo\",\"arguments\":\"\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"msg\\\":\\\"hi\\\"}\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"t2\",\"function\":{\"name\":\"upper\",\"arguments\":\"\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"function\":{\"arguments\":\"{\\\"msg\\\":\\\"bye\\\"}\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\",\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, %Req.Response{status: 200, headers: [], body: ""}}
    end)
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"content\":\"all done\"},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, %Req.Response{status: 200, headers: [], body: ""}}
    end)

    tools = Registry.to_api_format(reg)

    assert {:ok, "all done", _messages} =
             Orchestrator.run_messages(
               [%{role: "user", content: "run both"}],
               router: router,
               executor: exec,
               tools: tools,
               http_client: AIBrain.LLM.HTTPMock,
               on_event: fn event -> send(test_pid, event) end
             )

    assert_receive %{type: :tool_use_start_sse, tool_name: "echo", tool_use_id: "t1"}
    assert_receive %{type: :tool_use_start_sse, tool_name: "upper", tool_use_id: "t2"}

    assert_receive %{
      type: :tool_result,
      tool_use_id: "t1",
      result: {:ok, %AIBrain.Tool.Result{content: "echo:hi"}}
    }

    assert_receive %{
      type: :tool_result,
      tool_use_id: "t2",
      result: {:ok, %AIBrain.Tool.Result{content: "BYE"}}
    }

    assert_receive %{type: :turn_complete, text: "all done", stop_reason: :stop}
  end
end
