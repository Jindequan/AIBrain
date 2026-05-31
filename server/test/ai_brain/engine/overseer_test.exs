defmodule AIBrain.Engine.OverseerTest do
  use ExUnit.Case, async: false

  import Mox

  alias AIBrain.Engine.{Overseer, Transaction}
  alias AIBrain.Provider.{Info, Router}

  defmodule TestSink do
    @behaviour AIBrain.Engine.ResultSink

    def save_message(_tx_id, _message), do: :ok
    def save_result(_tx_id, _result), do: :ok
    def flush(_tx_id), do: :ok
    def load(_tx_id), do: {:error, :not_found}
    def list_running, do: []
  end

  setup :verify_on_exit!

  setup do
    overseer_name = Module.concat(__MODULE__, :"overseer_#{System.unique_integer([:positive])}")
    {:ok, _} = Overseer.start_link(name: overseer_name, max_concurrent: 5)

    # Start a minimal router + provider so executors have a valid turn loop
    provider = %Info{
      name: "test",
      api_key: "key-test",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: 1
    }

    {:ok, router} = Router.start_link(providers: [provider], name: nil)

    ctx = %{
      router: router,
      http_client: AIBrain.LLM.HTTPMock,
      caller: self(),
      caller_chain: [self()]
    }

    %{overseer: overseer_name, test_ctx: ctx}
  end

  test "start_transaction returns {:ok, executor_pid}", %{overseer: name, test_ctx: ctx} do
    AIBrain.LLM.HTTPMock
    |> stub(:post, fn _url, _opts ->
      Process.sleep(60_000)
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    tx = Transaction.new(:chat, "o-test-1", [%{role: "user"}], [])
    assert {:ok, pid} = Overseer.start_transaction(name, tx, TestSink, ctx)
    assert Process.alive?(pid)
  end

  test "list_active returns running transactions", %{overseer: name, test_ctx: ctx} do
    AIBrain.LLM.HTTPMock
    |> stub(:post, fn _url, _opts ->
      Process.sleep(60_000)
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    tx = Transaction.new(:run, "o-active-1", [%{role: "user"}], [])
    {:ok, _pid} = Overseer.start_transaction(name, tx, TestSink, ctx)

    active = Overseer.list_active(name)
    assert is_list(active)
    assert length(active) >= 1
  end

  test "count_active returns correct number", %{overseer: name, test_ctx: ctx} do
    AIBrain.LLM.HTTPMock
    |> stub(:post, fn _url, _opts ->
      Process.sleep(60_000)
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    tx1 = Transaction.new(:chat, "o-count-1", [%{role: "user"}], [])
    tx2 = Transaction.new(:chat, "o-count-2", [%{role: "user"}], [])

    {:ok, _pid1} = Overseer.start_transaction(name, tx1, TestSink, ctx)
    {:ok, _pid2} = Overseer.start_transaction(name, tx2, TestSink, ctx)

    assert Overseer.count_active(name) >= 2
  end
end
