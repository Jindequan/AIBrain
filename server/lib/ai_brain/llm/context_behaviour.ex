defmodule AIBrain.LLM.ContextBehaviour do
  @moduledoc """
  Behaviour for LLM.Context, enabling mock injection in tests.
  """

  @callback estimate_tokens(input :: term()) :: non_neg_integer()
end
