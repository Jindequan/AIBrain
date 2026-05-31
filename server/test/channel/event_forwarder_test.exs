defmodule AIBrain.Channel.EventForwarderTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.{Bus, EventForwarder}

  test "handler/2 forwards supported runtime events into surfaced channel replies" do
    {:ok, bus} = Bus.start_link(name: nil)
    handler = EventForwarder.handler(bus, channel: :cli)

    assert :ok =
             handler.(%{
               type: :sandbox_feedback,
               tool_use_id: "s1",
               operation: :workspace_write,
               result: :blocked,
               detail: "Writes outside the allowed workspace are blocked."
             })

    assert [
             %{
               role: "assistant",
               metadata: %{
                 surface: :operator_diagnostic,
                 diagnostic_type: :sandbox_feedback,
                 channel: :cli
               }
             }
           ] = Bus.published(bus)
  end

  test "handler/2 ignores unsupported runtime events" do
    {:ok, bus} = Bus.start_link(name: nil)
    handler = EventForwarder.handler(bus, channel: :cli)

    assert :ok = handler.(%{type: :text_delta, text: "hello"})
    assert [] = Bus.published(bus)
  end
end
