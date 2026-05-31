defmodule AIBrain.Engine.Transaction do
  @moduledoc """
  Represents a single runtime transaction (chat query, run execution, automation, delegated Assistant work).

  Status lifecycle:
    pending -> running -> completed
                     -> failed
                     -> aborted
    pending -> aborted
  """

  @type type :: :chat | :run | :automation | :assistant | :plan
  @type status :: :pending | :running | :completed | :failed | :aborted

  @enforce_keys [:id, :type, :messages, :tools]
  defstruct [
    :id,
    :type,
    :session_id,
    :parent_id,
    messages: [],
    tools: [],
    opts: [],
    status: :pending,
    result: nil,
    created_at: nil,
    completed_at: nil,
    retries: 0,
    max_turns: 200,
    max_wall_time: 1800,
    model: nil
  ]

  @valid_transitions %{
    pending: [:running, :aborted],
    running: [:completed, :failed, :aborted]
  }

  @doc """
  Create a new transaction with the given type, id, messages, tools, and optional overrides.
  """
  def new(type, id, messages, tools, overrides \\ []) do
    type = normalize_type(type)

    %__MODULE__{
      id: id,
      type: type,
      messages: messages,
      tools: tools,
      status: :pending,
      created_at: DateTime.utc_now(),
      opts: Keyword.get(overrides, :opts, []),
      session_id: Keyword.get(overrides, :session_id),
      parent_id: Keyword.get(overrides, :parent_id),
      max_turns: Keyword.get(overrides, :max_turns, 200),
      max_wall_time: Keyword.get(overrides, :max_wall_time, 1800),
      model: Keyword.get(overrides, :model)
    }
  end

  defp normalize_type(type) when type in ~w(chat run automation assistant plan)a, do: type

  @doc """
  Transition the transaction to a new status, enforcing lifecycle validity.
  """
  def update_status(%__MODULE__{status: current} = tx, new_status) do
    allowed = Map.get(@valid_transitions, current, [])

    if new_status in allowed do
      tx = %{tx | status: new_status}

      tx =
        if new_status in [:completed, :failed, :aborted] do
          %{tx | completed_at: DateTime.utc_now()}
        else
          tx
        end

      {:ok, tx}
    else
      :error
    end
  end

  @doc """
  Record the result of a transaction and mark it completed.
  """
  def record_result(%__MODULE__{} = tx, result) do
    tx = %{tx | result: result, status: :completed, completed_at: DateTime.utc_now()}
    {:ok, tx}
  end

  @doc """
  Mark the transaction as failed with a reason.
  """
  def record_failure(%__MODULE__{} = tx, reason) do
    tx = %{tx | result: {:error, reason}, status: :failed, completed_at: DateTime.utc_now()}
    {:ok, tx}
  end
end
