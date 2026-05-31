defmodule AIBrain.LLM.RetryTest do
  use ExUnit.Case, async: true
  alias AIBrain.LLM.Retry

  test "returns nil for non-429 status" do
    assert Retry.compute_retry_at(200, %{}, "") == nil
    assert Retry.compute_retry_at(500, %{}, "") == nil
  end

  test "parses retry-after as integer seconds" do
    now = System.os_time(:millisecond) / 1000
    result = Retry.compute_retry_at(429, %{"retry-after" => "60"}, "")
    assert_in_delta result, now + 60, 2.0
  end

  test "parses x-ratelimit-reset as unix timestamp (seconds)" do
    future = round(System.os_time(:millisecond) / 1000) + 300
    result = Retry.compute_retry_at(429, %{"x-ratelimit-reset" => "#{future}"}, "")
    assert result == future * 1.0
  end

  test "parses body hint 'in 30 seconds'" do
    now = System.os_time(:millisecond) / 1000
    result = Retry.compute_retry_at(429, %{}, "Rate limit exceeded. Retry in 30 seconds.")
    assert_in_delta result, now + 30, 2.0
  end

  test "falls back to 1-hour cooldown when no hint found" do
    now = System.os_time(:millisecond) / 1000
    result = Retry.compute_retry_at(429, %{}, "Too many requests")
    assert_in_delta result, now + 3600, 2.0
  end
end
