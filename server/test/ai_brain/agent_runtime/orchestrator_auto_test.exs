defmodule AIBrain.AgentRuntime.OrchestratorAutoTest do
  use AIBrain.DataCase
  import Mox

  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Data.{Runs}
  alias AIBrain.Provider.{Info, Router}
  alias AIBrain.Session.Store.Memory
  alias AIBrain.Tool.{Registry, Executor}

  setup :verify_on_exit!

  setup do
    data_dir =
      System.tmp_dir!() |> Path.join("auto_runtime_#{System.unique_integer([:positive])}")

    File.mkdir_p!(data_dir)
    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:ai_brain, :data_dir)
    end)

    :ok
  end

  defp provider do
    %Info{
      name: "auto-provider",
      api_key: "test-key",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: 1,
      enabled: true,
      models: %{"default" => %{"enabled" => true}}
    }
  end

  defp start_executor_with_tools(tools) do
    {:ok, reg} = Registry.start_link(name: nil)
    Enum.each(tools, &Registry.register(reg, &1))
    {:ok, exec} = Executor.start_link(registry: reg)
    {reg, exec}
  end

  test "auto chat creates a run even for simple messages" do
    {:ok, router} = Router.start_link(providers: [provider()], name: nil)
    {_reg, exec} = start_executor_with_tools([])
    {:ok, store} = Memory.start_link(name: nil)
    session_id = "auto-session-#{System.unique_integer([:positive])}"

    :ok =
      Memory.start_session(store, session_id, messages: [%{role: "user", content: "hello"}])

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data, "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"},\"index\":0}]}\n"},
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

    assert {:ok, %{run_id: run_id, result: {:ok, "hi", _history}}} =
             Orchestrator.resume_session_auto(session_id,
               session_store: store,
               router: router,
               executor: exec,
               tools: [],
               mode: "interactive",
               http_client: AIBrain.LLM.HTTPMock
             )

    assert is_binary(run_id)

    assert {:ok, run} = Runs.get_run(run_id)
    assert run.status == "completed"
    assert run.output_summary == "hi"

    assert {:ok, session} = Memory.load_session(store, session_id)
    assert Enum.any?(session.messages, &match?(%AIBrain.Message{role: "assistant"}, &1))
  end

  test "auto chat records failure when LLM call fails" do
    {:ok, router} = Router.start_link(providers: [provider()], name: nil)
    {_reg, exec} = start_executor_with_tools([])
    {:ok, store} = Memory.start_link(name: nil)
    session_id = "auto-failure-#{System.unique_integer([:positive])}"

    :ok =
      Memory.start_session(store, session_id, messages: [%{role: "user", content: "hello"}])

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, _opts ->
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    assert {:ok, %{run_id: run_id, result: {:error, _reason}}} =
             Orchestrator.resume_session_auto(session_id,
               session_store: store,
               router: router,
               executor: exec,
               tools: [],
               mode: "interactive",
               http_client: AIBrain.LLM.HTTPMock
             )

    assert is_binary(run_id)

    assert {:ok, run} = Runs.get_run(run_id)
    assert run.status == "failed"

    assert {:ok, session} = Memory.load_session(store, session_id)

    assert Enum.any?(session.messages, fn
             %AIBrain.Message{role: "assistant", metadata: %{"status" => "failed"}} -> true
             _ -> false
           end)
  end
end
