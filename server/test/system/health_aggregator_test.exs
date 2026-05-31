defmodule AIBrain.System.HealthAggregatorTest do
  use ExUnit.Case, async: true

  alias AIBrain.System.HealthAggregator, as: Aggregator

  describe "derive_status/2" do
    test "healthy when db ok, no errors" do
      metrics = %{llm_errors: 0, llm_calls: 10}
      assert Aggregator.derive_status(metrics, :ok) == :healthy
    end

    test "unhealthy when db is down" do
      assert Aggregator.derive_status(%{}, :error) == :unhealthy
    end

    test "degraded when error rate is high" do
      metrics = %{llm_errors: 8, llm_calls: 10}
      assert Aggregator.derive_status(metrics, :ok) == :degraded
    end
  end

  describe "snapshot/0" do
    test "returns a map with expected keys" do
      snap = Aggregator.snapshot()
      assert is_map(snap)
      assert Map.has_key?(snap, :system_status)
      assert Map.has_key?(snap, :uptime_seconds)
      assert Map.has_key?(snap, :checked_at)
      assert Map.has_key?(snap, :telemetry)
      assert Map.has_key?(snap, :recent_alerts)
      assert Map.has_key?(snap, :db)
      assert snap.system_status in [:healthy, :degraded, :unhealthy]
    end

    test "uptime is a positive integer" do
      snap = Aggregator.snapshot()
      assert is_integer(snap.uptime_seconds)
      assert snap.uptime_seconds >= 0
    end
  end
end
