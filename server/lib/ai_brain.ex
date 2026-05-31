defmodule AiBrain do
  @moduledoc """
  AIBrain — autonomous AI agent system.

  Core modules:
  - `AIBrain.Provider` — multi-provider LLM routing with failover
  - `AIBrain.LLM` — HTTP client and 429 retry parsing
  - `AIBrain.Tool` — behaviour contract, registry, and parallel executor
  - `AIBrain.AgentRuntime.Orchestrator` — top-level runtime entrypoint
  """

  @doc """
  Runs a query through the AIBrain runtime.

  ## Examples

      iex> function_exported?(AiBrain, :run, 2)
      true

  """
  def run(messages, opts \\ []) do
    AIBrain.AgentRuntime.Orchestrator.run_messages(messages, opts, %{source_type: "manual"})
  end
end
