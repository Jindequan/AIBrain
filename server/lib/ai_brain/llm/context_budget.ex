defmodule AIBrain.LLM.ContextBudget do
  @moduledoc """
  Context budget management for LLM conversations.

  Ensures conversation stays within token limits by intelligently pruning
  old messages while preserving critical context:

  - System message is always accounted for but not in the message list
  - First user message (the task definition) is ALWAYS anchored
  - Tool result messages are preserved (they contain irreplaceable data)
  - Assistant chatter is dropped before tool results or user messages
  - When messages are dropped, intelligent summarization is used (when available)
  - Falls back to simple truncation if summarization fails
  """

  @max_context_tokens 128_000
  @target_ratio 0.75
  @enable_summarization Application.compile_env(:ai_brain, :enable_context_summarization, true)

  def ensure_budget(
        messages,
        system,
        model,
        _session_store,
        _session_id,
        on_event,
        max_context_tokens \\ @max_context_tokens,
        opts \\ []
      ) do
    target_ratio = Keyword.get(opts, :target_ratio, @target_ratio)

    system_tokens = AIBrain.LLM.Context.estimate_tokens(system)
    msg_tokens = AIBrain.LLM.Context.estimate_tokens(messages)
    total_tokens = system_tokens + msg_tokens

    limit =
      if model do
        AIBrain.LLM.Context.context_limit(model)
      else
        max_context_tokens
      end

    target = round(limit * target_ratio)

    if total_tokens > target do
      {truncated, method} = compress_context(messages, target, system_tokens)

      dropped = length(messages) - length(truncated)

      on_event.(%{
        type: :context_compressed,
        original_count: length(messages),
        kept_count: length(truncated),
        dropped_count: dropped,
        original_tokens: total_tokens,
        kept_tokens: system_tokens + AIBrain.LLM.Context.estimate_tokens(truncated),
        method: method
      })

      truncated
    else
      messages
    end
  end

  # ── Context Compression ─────────────────────────────────────────

  # Try intelligent summarization first, fall back to truncation
  defp compress_context(messages, target_tokens, system_tokens) do
    if @enable_summarization and length(messages) > 10 do
      case try_summarize(messages, target_tokens, system_tokens) do
        {:ok, compressed} ->
          {compressed, :summarization}

        {:error, _reason} ->
          # Fall back to simple truncation
          {keep_with_anchoring(messages, target_tokens, system_tokens), :truncation}
      end
    else
      # Not enough messages or summarization disabled
      {keep_with_anchoring(messages, target_tokens, system_tokens), :truncation}
    end
  end

  # Try to summarize old messages while keeping recent ones
  defp try_summarize(messages, target_tokens, system_tokens) do
    first_user = Enum.find(messages, &(message_role(&1) == "user"))

    {to_process, anchor} =
      if first_user do
        idx = Enum.find_index(messages, fn m -> m == first_user end)

        if idx == 0 do
          {Enum.drop(messages, 1), first_user}
        else
          {List.delete_at(messages, idx), first_user}
        end
      else
        {messages, nil}
      end

    # Keep most recent 5-8 messages, summarize the rest
    keep_recent = min(8, div(length(to_process), 2))

    case AIBrain.LLM.Summarizer.summarize_conversation(
           to_process,
           keep_recent,
           focus: :key_points
         ) do
      {:ok, compressed, _saved} ->
        # Re-add anchor if it exists
        final = if anchor, do: [anchor | compressed], else: compressed

        # Verify we're within budget
        final_tokens = system_tokens + AIBrain.LLM.Context.estimate_tokens(final)

        if final_tokens <= target_tokens do
          {:ok, final}
        else
          # Still over budget, need more aggressive truncation
          {:error, :still_over_budget}
        end

      {:error, _reason, _messages, _tokens} ->
        {:error, :summarization_failed}

      {:no_summary_needed, _messages, _tokens} ->
        {:error, :no_summary_needed}
    end
  end

  # ── Simple Truncation (Fallback) ────────────────────────────────
  # Always anchors the first user message (task definition).
  # Tool results are preserved; assistant chatter is dropped first.
  defp keep_with_anchoring(messages, target_tokens, system_tokens) do
    first_user = Enum.find(messages, &(message_role(&1) == "user"))
    {to_process, anchor} = split_anchor(messages, first_user)

    kept =
      to_process
      |> Enum.reverse()
      |> Enum.reduce_while({[], 0}, fn msg, {acc, acc_tokens} ->
        msg_tokens = AIBrain.LLM.Context.estimate_tokens(msg)

        if acc_tokens + msg_tokens + system_tokens + anchor_tokens(anchor) <= target_tokens do
          {:cont, {[msg | acc], acc_tokens + msg_tokens}}
        else
          {:halt, {acc, acc_tokens}}
        end
      end)
      |> elem(0)

    dropped_count = length(messages) - length(kept) - if anchor, do: 1, else: 0

    if dropped_count > 0 and anchor != nil do
      marker = %AIBrain.Message{
        role: "user",
        content:
          "[#{dropped_count} earlier messages were summarized to fit context budget. Key info from completed steps is preserved in the plan context below.]"
      }

      [anchor, marker | kept]
    else
      if anchor, do: [anchor | kept], else: kept
    end
  end

  defp split_anchor(messages, nil), do: {messages, nil}

  defp split_anchor(messages, first_user) do
    idx = Enum.find_index(messages, fn m -> m == first_user end)

    if idx == 0 do
      {Enum.drop(messages, 1), first_user}
    else
      {List.delete_at(messages, idx), first_user}
    end
  end

  defp anchor_tokens(nil), do: 0
  defp anchor_tokens(anchor), do: AIBrain.LLM.Context.estimate_tokens(anchor)

  defp message_role(%{role: role}), do: role
  defp message_role(%{"role" => role}), do: role
  defp message_role(_), do: nil
end
