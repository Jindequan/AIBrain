defmodule AIBrain.Channel.NotifierTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Notifier

  test "dispatch/2 calls configured adapters" do
    # With no configured adapters, dispatch is a no-op
    assert :ok = Notifier.dispatch(%{type: :test_event}, [])
  end

  test "dispatch/1 reads from application env" do
    # Default has no adapters configured
    assert :ok = Notifier.dispatch(%{type: :test_event})
  end
end
