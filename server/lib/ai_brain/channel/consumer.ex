defmodule AIBrain.Channel.Consumer do
  @moduledoc """
  Minimal consumer facade that composes the channel bus, bridge, and event
  forwarder into a directly usable entrypoint.
  """

  alias AIBrain.Channel.{Bridge, Bus, EventForwarder}

  defstruct [:bus, :channel]

  def start_link(opts \\ []) do
    channel = Keyword.get(opts, :channel, :cli)

    with {:ok, bus} <- Bus.start_link(name: Keyword.get(opts, :name)) do
      {:ok, %__MODULE__{bus: bus, channel: channel}}
    end
  end

  def event_handler(%__MODULE__{bus: bus, channel: channel}) do
    EventForwarder.handler(bus, channel: channel)
  end

  def dispatch(%__MODULE__{bus: bus, channel: channel}, request, opts \\ [])
      when is_map(request) do
    request =
      case Map.has_key?(request, :channel) or Map.has_key?(request, "channel") do
        true -> request
        false -> Map.put(request, :channel, channel)
      end

    Bridge.dispatch(bus, request, opts)
  end

  def published(%__MODULE__{bus: bus}) do
    Bus.published(bus)
  end
end
