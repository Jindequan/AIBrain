defmodule AIBrain.Engine.TransactionTest do
  use ExUnit.Case, async: true

  alias AIBrain.Engine.Transaction

  test "new/4 creates transaction with defaults" do
    tx = Transaction.new(:chat, "tx-123", [], [])
    assert tx.id == "tx-123"
    assert tx.type == :chat
    assert tx.status == :pending
    assert %DateTime{} = tx.created_at
    assert tx.retries == 0
    assert tx.max_turns == 200
    assert tx.parent_id == nil
  end

  test "new/4 with optional fields" do
    tx =
      Transaction.new(:run, "tx-456", [%{role: "user"}], [%{"name" => "bash"}],
        max_turns: 50,
        parent_id: "tx-123"
      )

    assert tx.max_turns == 50
    assert tx.parent_id == "tx-123"
    assert length(tx.messages) == 1
  end

  test "update_status/2 transitions state" do
    tx = Transaction.new(:chat, "tx-1", [], [])
    assert {:ok, tx} = Transaction.update_status(tx, :running)
    assert tx.status == :running
    assert {:ok, tx} = Transaction.update_status(tx, :completed)
    assert tx.status == :completed
    assert %DateTime{} = tx.completed_at
  end

  test "update_status/2 rejects invalid transitions" do
    tx = Transaction.new(:chat, "tx-1", [], [])
    assert :error = Transaction.update_status(tx, :completed)
  end

  test "record_result/2 stores result" do
    tx = Transaction.new(:chat, "tx-1", [], [])
    {:ok, tx} = Transaction.update_status(tx, :running)
    {:ok, tx} = Transaction.record_result(tx, {:ok, "done", []})
    assert tx.result == {:ok, "done", []}
    assert tx.status == :completed
  end

  test "update_status/2 allows pending -> aborted" do
    tx = Transaction.new(:chat, "tx-1", [], [])
    assert {:ok, tx} = Transaction.update_status(tx, :aborted)
    assert tx.status == :aborted
    assert %DateTime{} = tx.completed_at
  end

  test "record_failure/2 marks transaction as failed" do
    tx = Transaction.new(:chat, "tx-1", [], [])
    {:ok, tx} = Transaction.update_status(tx, :running)
    {:ok, tx} = Transaction.record_failure(tx, "something broke")
    assert tx.result == {:error, "something broke"}
    assert tx.status == :failed
    assert %DateTime{} = tx.completed_at
  end

  test "type values are validated" do
    assert_raise FunctionClauseError, fn ->
      Transaction.new(:invalid_type, "x", [], [])
    end
  end
end
