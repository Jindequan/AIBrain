defmodule AIBrain.LLM.Summarizer do
  @moduledoc """
  Intelligent context summarization using LLM.

  When context exceeds budget, instead of simple truncation, this module
  uses the LLM to create semantic summaries that preserve key information
  while dramatically reducing token usage.
  """

  require Logger

  @doc """
  Summarize a list of messages into a compact representation.

  Returns a summary string and estimated token savings.
  """
  def summarize(messages, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, 2000)
    provider = Keyword.get(opts, :provider)
    focus = Keyword.get(opts, :focus, :key_points)

    # Estimate current token count
    current_tokens = estimate_messages_tokens(messages)

    if current_tokens <= max_tokens do
      {:no_summary_needed, messages, current_tokens}
    else
      perform_summarization(messages, max_tokens, provider, focus)
    end
  end

  @doc """
  Summarize old conversation turns while preserving recent context.
  """
  def summarize_conversation(messages, keep_recent \\ 5, opts \\ []) do
    if length(messages) <= keep_recent * 2 do
      {:no_summary_needed, messages, estimate_messages_tokens(messages)}
    else
      {recent, old} = Enum.split(messages, -keep_recent)

      case summarize(old, opts) do
        {:ok, summary, _saved} ->
          # Create a synthetic "system" message with the summary
          summary_msg = %{
            "role" => "system",
            "content" => "[Earlier conversation summary: #{summary}]"
          }

          {:ok, [summary_msg | recent], estimate_messages_tokens([summary_msg | recent])}

        {:no_summary_needed, old_messages, _tokens} ->
          compressed = old_messages ++ recent
          {:ok, compressed, estimate_messages_tokens(compressed)}

        {:error, reason} ->
          Logger.warning(
            "Summarizer: failed to summarize, using original messages: #{inspect(reason)}"
          )

          {:error, reason, messages, estimate_messages_tokens(messages)}
      end
    end
  end

  # ── Private ─────────────────────────────────────────────────

  defp perform_summarization(messages, _target_tokens, provider, focus) do
    prompt = build_summary_prompt(messages, focus)

    # Select provider if not specified
    provider =
      if provider do
        provider
      else
        case AIBrain.Provider.SmartRouter.select(
               AIBrain.Provider.Router,
               %{model: nil, tools: [], turn: 0, retries: 0}
             ) do
          {:ok, p} -> p
          _ -> nil
        end
      end

    if provider do
      messages = [%{role: "user", content: prompt}]

      # Collect the LLM response
      case call_llm(provider, messages) do
        {:ok, summary} ->
          # Verify the summary is actually shorter
          summary_tokens = AIBrain.LLM.Context.estimate_tokens(summary)
          original_tokens = estimate_messages_tokens(messages)

          saved = original_tokens - summary_tokens

          if saved > 0 do
            {:ok, summary, saved}
          else
            {:error, :summary_not_shorter}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_provider_available}
    end
  end

  defp build_summary_prompt(messages, focus) do
    messages_text =
      Enum.map(messages, fn msg ->
        role = msg[:role] || msg["role"] || "unknown"
        content = msg[:content] || msg["content"] || ""
        "##{role}: #{content}"
      end)
      |> Enum.join("\n\n")

    focus_instruction =
      case focus do
        :key_points -> "Focus on key points, decisions, and outcomes."
        :technical -> "Focus on technical details, code changes, and error messages."
        :actions -> "Focus on actions taken and their results."
        _ -> "Capture the essential information concisely."
      end

    """
    Summarize the following conversation #{focus_instruction}

    Original conversation:
    #{messages_text}

    Provide a concise summary (max 3-4 sentences) that preserves:
    - What was being discussed
    - Key decisions or conclusions
    - Any important technical details or code changes
    - Current status or next steps

    Summary:
    """
  end

  defp call_llm(provider, messages) do
    # Use a simple non-streaming call
    try do
      {:ok, :streaming_complete} =
        AIBrain.LLM.Client.stream(
          provider,
          messages,
          [],
          on_event: fn _ -> :ok end
        )

      # Collect the response
      collect_response()
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp collect_response(acc \\ "") do
    receive do
      {:sse_event, %{text: text}} ->
        collect_response(acc <> text)

      {:sse_done} ->
        {:ok, String.trim(acc)}

      _ ->
        collect_response(acc)
    after
      30_000 ->
        {:ok, String.trim(acc)}
    end
  end

  defp estimate_messages_tokens(messages) do
    text =
      Enum.map(messages, fn msg ->
        content = msg[:content] || msg["content"] || ""
        role = msg[:role] || msg["role"] || ""
        "#{role}: #{content}"
      end)
      |> Enum.join("\n")

    AIBrain.LLM.Context.estimate_tokens(text)
  end
end
