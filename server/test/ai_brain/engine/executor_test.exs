defmodule AIBrain.Engine.ExecutorTest do
  use ExUnit.Case, async: false

  import Mox

  alias AIBrain.Engine.{Executor, Transaction}
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
    provider = %Info{
      name: "test",
      api_key: "key-test",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: 1
    }

    {:ok, router} = Router.start_link(providers: [provider], name: nil)

    # Default stub: keep worker alive for cancel/status/tx_id tests
    AIBrain.LLM.HTTPMock
    |> stub(:post, fn _url, _opts ->
      Process.sleep(60_000)
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    %{router: router}
  end

  describe "basic lifecycle" do
    test "executor processes a transaction and reports completion", %{router: router} do
      expect_stream_text("done")
      tx = Transaction.new(:chat, "exec-done-1", [%{role: "user", content: "hi"}], [])

      {:ok, _pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: %{router: router, http_client: AIBrain.LLM.HTTPMock, caller_chain: [self()]},
          caller: self()
        )

      assert_receive {:transaction_complete, "exec-done-1", _result}, 1000
    end

    test "executor reports tx_id and result via completion message", %{router: router} do
      expect_stream_text("done")
      tx = Transaction.new(:chat, "exec-txid-1", [%{role: "user", content: "hi"}], [])

      {:ok, _pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: %{router: router, http_client: AIBrain.LLM.HTTPMock, caller_chain: [self()]},
          caller: self()
        )

      assert_receive {:transaction_complete, "exec-txid-1", result}, 1000
      assert tuple_size(result) > 0
    end
  end

  describe "cancel" do
    test "cancel/1 kills the worker and stops the executor process", %{router: router} do
      ctx = %{
        router: router,
        http_client: AIBrain.LLM.HTTPMock,
        caller: self(),
        caller_chain: [self()]
      }

      tx = Transaction.new(:chat, "exec-cancel-1", [%{role: "user", content: "hi"}], [])

      {:ok, pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: ctx,
          caller: self()
        )

      assert Process.alive?(pid)
      assert :ok = Executor.cancel(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "cancel sends {:transaction_complete, ..., {:error, :cancelled}} to caller",
         %{router: router} do
      ctx = %{
        router: router,
        http_client: AIBrain.LLM.HTTPMock,
        caller: self(),
        caller_chain: [self()]
      }

      tx = Transaction.new(:chat, "exec-cancel-2", [%{role: "user", content: "hi"}], [])

      {:ok, pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: ctx,
          caller: self()
        )

      Executor.cancel(pid)
      assert_receive {:transaction_complete, "exec-cancel-2", {:error, :cancelled}}, 500
    end
  end

  describe "status queries" do
    test "status/1 returns the transaction struct", %{router: router} do
      ctx = %{
        router: router,
        http_client: AIBrain.LLM.HTTPMock,
        caller: self(),
        caller_chain: [self()]
      }

      tx = Transaction.new(:chat, "exec-status-1", [%{role: "user", content: "hi"}], [])

      {:ok, pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: ctx,
          caller: self()
        )

      assert {:ok, %{id: "exec-status-1", status: status}} = Executor.status(pid)
      assert status in [:pending, :running]
    end

    test "tx_id/1 returns the transaction id", %{router: router} do
      ctx = %{
        router: router,
        http_client: AIBrain.LLM.HTTPMock,
        caller: self(),
        caller_chain: [self()]
      }

      tx = Transaction.new(:chat, "exec-txid-q-1", [%{role: "user", content: "hi"}], [])

      {:ok, pid} =
        Executor.start_link(
          tx: tx,
          sink: TestSink,
          ctx: ctx,
          caller: self()
        )

      assert "exec-txid-q-1" = Executor.tx_id(pid)
    end
  end

  defp expect_stream_text(text) do
    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data,
                  "data: {\"choices\":[{\"delta\":{\"content\":\"#{text}\"},\"index\":0}]}\n"},
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
  end
end
