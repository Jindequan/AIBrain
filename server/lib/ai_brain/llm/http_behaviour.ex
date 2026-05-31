defmodule AIBrain.LLM.HTTPBehaviour do
  @moduledoc """
  Behaviour for making streaming HTTP POST requests to LLM endpoints.

  Separating this from `Req` directly allows tests to inject a mock
  without touching the network.
  """

  @doc """
  Issues a streaming POST to `url` with `headers` and a JSON-encoded `body`.

  The `into` function is called for each chunk of data as it arrives.
  It must have the same arity/contract as the `into:` callback accepted
  by `Req.post/2`.

  Returns:
  - `{:ok, %Req.Response{}}` on success (status 2xx or any status when
    the server does respond — Req does not raise on non-2xx with `into:`).
  - `{:error, exception}` on a transport-level failure (TCP refused,
    TLS error, timeout, etc.).
  """
  @callback post(url :: String.t(), opts :: keyword()) ::
              {:ok, Req.Response.t()} | {:error, Exception.t()}
end
