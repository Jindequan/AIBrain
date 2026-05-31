defmodule AIBrain.Engine.ResultSink.PlanSink do
  @moduledoc """
  ResultSink for Planning Agent transactions.

  Captures ask_question events in ETS so the caller can read them
  and inject user answers back into the agent's conversation.

  Does NOT persist to DB -- planning session state lives only in the
  Engine.Executor's in-memory messages.
  """

  @behaviour AIBrain.Engine.ResultSink

  alias AIBrain.MessageLog

  @table :plan_sink_events

  @impl true
  def save_message(plan_id, message) do
    MessageLog.append(MessageLog.messages_path("plans", plan_id), message)
    :ok
  end

  @impl true
  def save_result(tx_id, {:ok, text, _history}), do: store_result(tx_id, {:ok, text})
  def save_result(tx_id, {:ok, text}), do: store_result(tx_id, {:ok, text})
  def save_result(tx_id, {:error, reason}), do: store_result(tx_id, {:error, reason})

  @impl true
  def flush(_tx_id), do: :ok

  @impl true
  def load(tx_id) do
    case :ets.lookup(@table, tx_id) do
      [{^tx_id, {:ok, text}}] -> {:ok, %{result: :ok, text: text}}
      [{^tx_id, {:error, reason}}] -> {:ok, %{result: :error, reason: reason}}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @impl true
  def list_running, do: []

  @doc "Store a question event from the Planning Agent so the caller can retrieve it."
  def store_question(tx_id, question) do
    ensure_table()
    :ets.insert(@table, {:question, tx_id, question})
  end

  @doc "Retrieve and clear all pending questions for a planning session."
  def pop_questions(tx_id) do
    ensure_table()
    keys = :ets.match(@table, {:question, tx_id, :"$1"})
    :ets.match_delete(@table, {:question, tx_id, :_})
    List.flatten(keys)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:bag, :public, :named_table])
      _ -> :ok
    end
  end

  defp store_result(tx_id, result) do
    ensure_table()
    :ets.insert(@table, {tx_id, result})
    :ok
  end
end
