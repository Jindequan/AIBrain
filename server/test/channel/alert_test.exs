defmodule AIBrain.Channel.AlertTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Alert

  describe "new/5" do
    test "creates an alert with severity and message" do
      alert = Alert.new(:warning, :director, "step_exhausted", "Step failed")
      assert alert.severity == :warning
      assert alert.source == :director
      assert alert.type == "step_exhausted"
      assert alert.message == "Step failed"
      assert alert.dedup_key == "director:step_exhausted"
    end

    test "uses custom dedup key when provided" do
      alert = Alert.new(:critical, :monitor, "timeout", "msg", dedup_key: "custom:key")
      assert alert.dedup_key == "custom:key"
    end

    test "sets default cooldowns per severity" do
      critical = Alert.new(:critical, :test, "x", "msg")
      warning = Alert.new(:warning, :test, "x", "msg")
      info = Alert.new(:info, :test, "x", "msg")

      assert critical.cooldown_ms == 60_000
      assert warning.cooldown_ms == 300_000
      assert info.cooldown_ms == 900_000
    end

    test "accepts custom cooldown" do
      alert = Alert.new(:warning, :test, "x", "msg", cooldown_ms: 10_000)
      assert alert.cooldown_ms == 10_000
    end

    test "stores metadata" do
      alert = Alert.new(:info, :test, "x", "msg", metadata: %{plan_id: "p1"})
      assert alert.metadata.plan_id == "p1"
    end
  end

  describe "suppressed?/2" do
    test "returns false when no recent alerts match" do
      alert = Alert.new(:warning, :src, "type", "msg")
      refute Alert.suppressed?(alert, [])
    end

    test "returns true when same dedup key fired within cooldown" do
      alert = Alert.new(:warning, :src, "type", "msg", cooldown_ms: 60_000)
      now = System.system_time(:millisecond)
      assert Alert.suppressed?(alert, [{"src:type", now - 30_000}])
    end

    test "returns false when same key fired outside cooldown" do
      alert = Alert.new(:warning, :src, "type", "msg", cooldown_ms: 5000)
      now = System.system_time(:millisecond)
      refute Alert.suppressed?(alert, [{"src:type", now - 10_000}])
    end

    test "returns false for different dedup key" do
      alert = Alert.new(:warning, :src, "type_a", "msg", cooldown_ms: 60_000)
      now = System.system_time(:millisecond)
      refute Alert.suppressed?(alert, [{"src:type_b", now - 10_000}])
    end
  end
end
