defmodule AIBrain.Channel.Adapter do
  @moduledoc """
  Behaviour for channel adapters (Telegram, Slack, etc).
  """

  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, reason :: term()}
  @callback send_message(state :: term(), message :: map()) ::
              {:ok, state :: term()} | {:error, reason :: term()}
  @callback handle_inbound(state :: term(), payload :: map()) ::
              {:ok, [map()], state :: term()} | {:error, reason :: term()}
end
