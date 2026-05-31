defmodule AIBrain.Channel.EventForwarder do
  @moduledoc """
  Adapts runtime events into surfaced channel replies through the bridge.
  """

  alias AIBrain.Channel.Bridge

  def handler(bus, opts \\ []) do
    fn event ->
      case Bridge.dispatch_event(bus, event, opts) do
        {:ok, _reply} -> :ok
        {:error, :unsupported_request} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
