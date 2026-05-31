defmodule AIBrain.Engine.ResultSink.TaskSink do
  @moduledoc """
  ResultSink for task direct-execution runs.
  Persists each turn to tasks/<task_id>/messages.jsonl.
  """

  @behaviour AIBrain.Engine.ResultSink

  alias AIBrain.MessageLog

  @impl true
  def save_message(task_id, message) do
    MessageLog.append(MessageLog.messages_path("tasks", task_id), message)
    :ok
  end

  @impl true
  def save_result(_task_id, _result), do: :ok

  @impl true
  def flush(_task_id), do: :ok

  @impl true
  def load(_task_id), do: {:error, :not_found}

  @impl true
  def list_running, do: []
end
