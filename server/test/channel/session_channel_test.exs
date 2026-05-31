defmodule AIBrain.Channel.SessionChannelTest do
  use AIBrain.DataCase, async: false

  import Mox

  alias AIBrain.Session.Store.Memory
  alias AIBrain.Channel.SessionChannel
  alias AIBrain.Provider.{Info, Router}
  alias AIBrain.Tool.{Executor, Registry}

  setup :verify_on_exit!

  defmodule WriteEchoTool do
    @behaviour AIBrain.Tool.Behaviour

    def name, do: "write_echo"
    def description, do: "mutating test tool"
    def input_schema, do: %{type: "object", properties: %{msg: %{type: "string"}}}
    def read_only?, do: false
    def risk_category, do: :workspace_write
    def execute(%{"msg" => msg}, _ctx), do: {:ok, "WRITE: #{msg}"}
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
    {:ok, reg} =
      Registry.start_link(name: :"session_channel_reg_#{System.unique_integer([:positive])}")

    Enum.each(tools, &Registry.register(reg, &1))
    Enum.each(tools, fn tool -> assert {:ok, ^tool} = Registry.lookup(reg, tool.name()) end)
    {:ok, exec} = Executor.start_link(registry: reg)
    exec
  end

  test "run/3 forwards runtime permission events into surfaced channel replies" do
    provider = make_provider("p1", 1)
    {:ok, router} = Router.start_link(providers: [provider], name: nil)
    exec = start_executor_with_tools([WriteEchoTool])
    test_pid = self()

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"t1\",\"function\":{\"name\":\"write_echo\",\"arguments\":\"\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"msg\\\":\\\"blocked\\\"}\"}}]},\"index\":0}]}\n"},
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
                  "data: {\"choices\":[{\"delta\":{\"content\":\"done\"},\"index\":0}]}\n"},
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

    assert {:ok, channel} = SessionChannel.start_link(channel: :cli)

    assert {:ok, "done", _messages} =
             SessionChannel.run(
               channel,
               [%{role: "user", content: "hello test with success criteria"}],
               router: router,
               executor: exec,
               tools: [],
               mode: :plan,
               http_client: AIBrain.LLM.HTTPMock,
               on_event: fn event -> send(test_pid, event) end
             )

    assert_receive %{type: :permission_checked, tool_name: "write_echo", decision: :denied}

    assert [
             %{
               role: "assistant",
               metadata: %{
                 surface: :operator_diagnostic,
                 diagnostic_type: :permission_denial,
                 channel: :cli
               }
             }
           ] = SessionChannel.published(channel)
  end

  test "status/3 returns compact session info from the session store" do
    {:ok, store} = Memory.start_link(name: nil)

    assert :ok =
             Memory.start_session(store, "status-1",
               requested_model: "claude-test",
               metadata: %{requested_model: "claude-test"}
             )

    assert {:ok, channel} = SessionChannel.start_link(channel: :cli)

    assert {:ok,
            %{
              session_id: "status-1",
              metadata: %{requested_model: "claude-test"}
            }} = SessionChannel.status(channel, "status-1", session_store: store)
  end

  test "export/3 delegates session export through the session store" do
    {:ok, store} = Memory.start_link(name: nil)

    assert :ok =
             Memory.start_session(store, "export-1",
               messages: [%{role: "user", content: "secret prompt"}],
               requested_model: "claude-test",
               metadata: %{
                 capabilities: %{
                   enabled: [%{name: "review-kit", source: :user}],
                   rejected: []
                 }
               }
             )

    assert :ok =
             Memory.append_message(store, "export-1", %{
               role: "assistant",
               content: "secret output"
             })

    assert {:ok, channel} = SessionChannel.start_link(channel: :cli)

    assert {:ok,
            %{
              session_id: "export-1"
            }} =
             SessionChannel.export(channel, "export-1", session_store: store)
  end

  test "resume/3 reuses stored session messages and forwards surfaced runtime events" do
    provider = make_provider("p1", 1)
    {:ok, router} = Router.start_link(providers: [provider], name: nil)
    exec = start_executor_with_tools([WriteEchoTool])
    {:ok, store} = Memory.start_link(name: nil)
    test_pid = self()

    assert :ok =
             Memory.start_session(store, "resume-1",
               messages: [%{role: "user", content: "hello test with success criteria"}],
               requested_model: "claude-test"
             )

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"t2\",\"function\":{\"name\":\"write_echo\",\"arguments\":\"\"}}]},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"msg\\\":\\\"blocked\\\"}\"}}]},\"index\":0}]}\n"},
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
                  "data: {\"choices\":[{\"delta\":{\"content\":\"done\"},\"index\":0}]}\n"},
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

    assert {:ok, channel} = SessionChannel.start_link(channel: :cli)

    assert {:ok, "done", _messages} =
             SessionChannel.resume(
               channel,
               "resume-1",
               router: router,
               executor: exec,
               tools: [],
               mode: :plan,
               session_store: store,
               http_client: AIBrain.LLM.HTTPMock,
               on_event: fn event -> send(test_pid, event) end
             )

    assert_receive %{type: :permission_checked, tool_name: "write_echo", decision: :denied}

    assert [
             %{
               role: "assistant",
               metadata: %{
                 surface: :operator_diagnostic,
                 diagnostic_type: :permission_denial,
                 channel: :cli
               }
             }
           ] = SessionChannel.published(channel)
  end
end
