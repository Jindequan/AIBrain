defmodule AIBrain.LLM.Retry do
  @fallback_cooldown_seconds 3600

  def compute_retry_at(status, headers, body) when status == 429 do
    now = System.os_time(:millisecond) / 1000
    h = normalize_headers(headers)

    from_header(h, now) || from_body(body, now) || now + @fallback_cooldown_seconds
  end

  def compute_retry_at(_status, _headers, _body), do: nil

  defp normalize_headers(h) do
    Enum.into(h, %{}, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
  end

  defp from_header(h, now) do
    cond do
      v = h["retry-after"] ->
        parse_retry_after(v, now)

      v = h["x-ratelimit-reset"] ->
        parse_unix(v)

      v =
          Enum.find_value(
            ~w[x-ratelimit-reset-requests x-ratelimit-reset-tokens ratelimit-reset],
            &h[&1]
          ) ->
        parse_unix(v)

      true ->
        nil
    end
  end

  defp parse_retry_after(v, now) do
    case Integer.parse(v) do
      {n, ""} -> now + n
      _ -> nil
    end
  end

  defp parse_unix(v) do
    case Integer.parse(v) do
      {ts, ""} when ts > 10_000_000_000 -> ts / 1000.0
      {ts, ""} -> ts * 1.0
      _ -> nil
    end
  end

  defp safe_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp from_body(body, now) do
    patterns = [
      {~r/in\s+(\d+)\s*s(?:ec(?:ond)?s?)?(?:\b|\.)/i, fn [_, n] -> now + safe_int(n) end},
      {~r/retry\s+after\s+(\d+)\s*s(?:ec(?:ond)?s?)?/i, fn [_, n] -> now + safe_int(n) end},
      {~r/in\s+(\d+)\s*min(?:ute)?s?/i, fn [_, n] -> now + safe_int(n) * 60 end},
      {~r/in\s+(\d+)\s*h(?:ou?r)?s?/i, fn [_, n] -> now + safe_int(n) * 3600 end}
    ]

    Enum.find_value(patterns, fn {re, calc} ->
      case Regex.run(re, body || "") do
        nil -> nil
        m -> calc.(m)
      end
    end)
  end
end
