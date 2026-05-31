defmodule AIBrain.LLM.MockHTTP do
  @moduledoc "Stub for LLM.Client HTTP calls in tests — not used yet, placeholder for Task 11."
  def post(_url, _headers, _body, _on_chunk), do: {:ok, %{status: 200}}
end
