defmodule AIBrain.LLM.Context do
  @moduledoc """
  Context window tracking for LLM conversations.

  Provides token estimation and model context-limit lookups.
  Actual context pruning is handled by `AIBrain.LLM.ContextBudget`.
  """

  @behaviour AIBrain.LLM.ContextBehaviour

  @default_context_limit 200_000

  @known_limits %{
    "claude-3-5-sonnet" => 200_000,
    "claude-3-opus" => 200_000,
    "claude-3-haiku" => 200_000,
    "claude-4" => 200_000,
    "deepseek" => 1_000_000,
    "kimi" => 128_000,
    "gpt-4" => 128_000,
    "gpt-4o" => 128_000
  }

  @doc """
  Estimate tokens for a text — informational/debug only.
  Not used for runtime decisions.
  """
  def estimate_tokens(text) when is_binary(text) do
    char_count = String.length(text)
    cjk = count_cjk(text)
    non_cjk = max(0, char_count - cjk)
    cjk + div(non_cjk, 4) + 1
  end

  def estimate_tokens(%{content: content}) when is_binary(content) do
    estimate_tokens(content) + 3
  end

  def estimate_tokens(%{content: content}) when is_list(content) do
    Enum.reduce(content, 0, fn c, acc -> acc + estimate_tokens(c) end)
  end

  def estimate_tokens(%{type: "tool_use", input: input}) do
    estimate_tokens(inspect(input)) + 5
  end

  def estimate_tokens(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn m, acc -> acc + estimate_tokens(m) end)
  end

  def estimate_tokens(%{__struct__: _} = struct), do: estimate_tokens(inspect(struct))
  def estimate_tokens(%{} = map), do: estimate_tokens(inspect(map))

  @doc """
  Get context limit for a model string. Matches by prefix.
  """
  def context_limit(model) when is_binary(model) do
    model_lower = String.downcase(model)

    @known_limits
    |> Enum.find_value(@default_context_limit, fn {key, limit} ->
      if String.contains?(model_lower, key), do: limit
    end)
  end

  def context_limit(_model), do: @default_context_limit

  defp count_cjk(text) do
    text
    |> String.graphemes()
    |> Enum.count(fn g ->
      cp = String.to_charlist(g) |> hd()

      in_range?(cp, 0x4E00, 0x9FFF) or
        in_range?(cp, 0x3400, 0x4DBF) or
        in_range?(cp, 0x2E80, 0x2EFF)
    end)
  end

  defp in_range?(val, lo, hi), do: val >= lo and val <= hi
end
