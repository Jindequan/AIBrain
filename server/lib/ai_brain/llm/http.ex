defmodule AIBrain.LLM.HTTP do
  @moduledoc "Real HTTP adapter — delegates to `Req`."
  @behaviour AIBrain.LLM.HTTPBehaviour

  @impl true
  def post(url, opts), do: Req.post(url, opts)
end
