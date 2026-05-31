defmodule AIBrain.Engine.ResultSink do
  @moduledoc """
  Behaviour for persisting transaction results.

  Each transaction type (chat, run, automation) implements its own sink
  so that Engine.Executor can persist without knowing storage details.
  """

  @callback save_message(tx_id :: String.t(), message :: map()) :: :ok
  @callback save_result(tx_id :: String.t(), result :: term()) :: :ok
  @callback flush(tx_id :: String.t()) :: :ok | {:error, term()}
  @callback load(tx_id :: String.t()) :: {:ok, map()} | {:error, :not_found}

  @doc """
  Collect metadata about running transactions for recovery.
  Each sink must return a list of transaction IDs that are still running.
  """
  @callback list_running() :: [String.t()]
end
