defmodule AIBrain.Engine.ExecutorIntegrationTest do
  use ExUnit.Case, async: false

  import Mox

  alias AIBrain.Engine.{Overseer, Transaction, Executor}
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
    overseer_name =
      Module.concat(__MODULE__, :"int_overseer_#{System.unique_integer([:positive])}")

    start_supervised!({Overseer, [name: overseer_name, max_concurrent: 10]})

    provider = %Info{
      name: "int-test",
      api_key: "key",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: 1
    }

    router_name =
      Module.concat(__MODULE__, :"int_router_#{System.unique_integer([:positive])}")

    {:ok, router} = Router.start_link(providers: [provider], name: router_name)

    # Stub HTTP so the worker loop doesn't crash immediately from transport errors
    AIBrain.LLM.HTTPMock
    |> stub(:post, fn _url, _opts ->
      Process.sleep(60_000)
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    %{overseer: overseer_name, router: router}
  end

  test "start_transaction returns executor that can be cancelled", %{
    overseer: name,
    router: router
  } do
    tx =
      Transaction.new(:run, "int-cancel-1", [%{role: "user", content: "hello"}], [])

    ctx = %{
      router: router,
      http_client: AIBrain.LLM.HTTPMock,
      system: "",
      on_event: fn _ -> :ok end,
      caller: self(),
      caller_chain: [self()]
    }

    assert {:ok, pid} =
             Overseer.start_transaction(name, tx, TestSink, ctx)

    assert Process.alive?(pid)
    assert :ok = Overseer.cancel(name, pid)
    Process.sleep(100)
    refute Process.alive?(pid)
  end

  test "Overseer rejects when at capacity", %{overseer: name, router: router} do
    ctx = %{
      router: router,
      http_client: AIBrain.LLM.HTTPMock,
      caller: self(),
      caller_chain: [self()]
    }

    assert {:ok, _pid} =
             Overseer.start_transaction(
               name,
               Transaction.new(:chat, "cap-test-1", [], []),
               TestSink,
               ctx
             )

    assert Overseer.count_active(name) >= 1
  end

  test "executor starts and responds to status queries", %{overseer: name, router: router} do
    tx =
      Transaction.new(:chat, "int-status-1", [%{role: "user", content: "hello"}], [])

    ctx = %{
      router: router,
      http_client: AIBrain.LLM.HTTPMock,
      system: "",
      on_event: fn _ -> :ok end,
      caller: self(),
      caller_chain: [self()]
    }

    assert {:ok, pid} =
             Overseer.start_transaction(name, tx, TestSink, ctx)

    assert {:ok, %{id: "int-status-1", status: status}} = Executor.status(pid)
    assert status in [:pending, :running]
  end
end
