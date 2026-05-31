defmodule AIBrain.Channel.BusTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.{Alert, Bus}

  test "publish/2 stores outbound channel messages in order" do
    {:ok, bus} = Bus.start_link(name: nil)

    assert :ok = Bus.publish(bus, %{role: "assistant", content: "one"})
    assert :ok = Bus.publish(bus, %{role: "assistant", content: "two"})

    assert [
             %{role: "assistant", content: "one"},
             %{role: "assistant", content: "two"}
           ] = Bus.published(bus)
  end

  describe "Alert publishing" do
    test "publishes alert structs" do
      {:ok, bus} = Bus.start_link(name: nil)
      alert = Alert.new(:warning, :test, "test_event", "test message")

      assert :ok = Bus.publish(bus, alert)
      [published] = Bus.published(bus)
      assert %Alert{} = published
      assert published.message == "test message"
    end

    test "deduplicates alerts within cooldown" do
      {:ok, bus} = Bus.start_link(name: nil)
      alert = Alert.new(:warning, :test, "test_event", "msg", cooldown_ms: 60_000)

      assert :ok = Bus.publish(bus, alert)
      assert {:suppressed, "test:test_event"} = Bus.publish(bus, alert)

      assert length(Bus.published(bus)) == 1
    end

    test "does not suppress different dedup keys" do
      {:ok, bus} = Bus.start_link(name: nil)
      a1 = Alert.new(:warning, :test, "type_a", "msg", cooldown_ms: 60_000)
      a2 = Alert.new(:warning, :test, "type_b", "msg", cooldown_ms: 60_000)

      assert :ok = Bus.publish(bus, a1)
      assert :ok = Bus.publish(bus, a2)

      published = Bus.published(bus)
      assert length(published) == 2
    end
  end

  describe "recent/2" do
    test "returns last N messages" do
      {:ok, bus} = Bus.start_link(name: nil)

      Bus.publish(bus, %{type: :a})
      Bus.publish(bus, %{type: :b})
      Bus.publish(bus, %{type: :c})

      assert length(Bus.recent(bus, 2)) == 2
    end
  end
end
