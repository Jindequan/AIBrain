defmodule AIBrain.Engine.Loop do
  @moduledoc """
  Pure stateless turn pipeline for LLM agent loops.

  All functions are data-in/data-out with no side effects. SSE collection,
  provider selection, and session persistence are handled by Engine.Executor.
  """

  alias AIBrain.Tool.{Error, Result}

  @doc """
  Apply context budget to messages. Pure: takes messages, returns messages.
  """
  def prepare_messages(messages, system, model, opts) do
    AIBrain.LLM.ContextBudget.ensure_budget(
      messages,
      system,
      model,
      nil,
      nil,
      Keyword.get(opts, :on_event, fn _ -> :ok end),
      Keyword.get(opts, :max_context_tokens, 128_000)
    )
  end

  @doc """
  Compact transaction state messages to prevent unbounded growth.

  Uses a tighter target ratio (50%) than prepare_messages (75%) to ensure
  the stored state stays well within budget across repeated turns.
  Unlike prepare_messages, the result REPLACES tx.messages rather than
  being an ephemeral snapshot for a single API call.

  The context limit comes from `ctx[:max_context_tokens]`, which is set
  by the Executor from the selected provider's DB-configured value —
  no hardcoded model→limit map needed.
  """
  def compact_state(messages, ctx) do
    max_tokens = ctx[:max_context_tokens] || 128_000
    system = ctx[:system] || ""
    on_event = ctx[:on_event] || fn _ -> :ok end

    AIBrain.LLM.ContextBudget.ensure_budget(
      messages,
      system,
      nil,
      nil,
      nil,
      on_event,
      max_tokens,
      target_ratio: 0.50
    )
  end

  @doc """
  Execute authorized tools and return {id, name, result} tuples.
  """
  def execute_tools(tool_uses, executor, context, authorize_tool) do
    decisions =
      Enum.map(tool_uses, fn tool_use ->
        case authorize_tool.(tool_use) do
          :allow -> {tool_use, {:allow, tool_use}}
          {:allow, authorized_tool_use} -> {tool_use, {:allow, authorized_tool_use}}
          {:deny, reason} -> {tool_use, {:deny, reason}}
          {:suspend, meta} -> {tool_use, {:suspend, meta}}
        end
      end)

    case Enum.find(decisions, fn {_tool_use, decision} -> match?({:suspend, _}, decision) end) do
      {_tool_use, {:suspend, meta}} ->
        {:suspended, meta}

      nil ->
        execute_decisions(decisions, executor, context)
    end
  end

  defp execute_decisions(decisions, executor, context) do
    allowed =
      for {_original, {:allow, authorized_tool_use}} <- decisions, do: authorized_tool_use

    allowed_results =
      AIBrain.Tool.Executor.run(executor, allowed, context)
      |> Map.new()

    Enum.map(decisions, fn {tool_use, decision} ->
      case decision do
        {:allow, _} ->
          {tool_use.id, tool_use.name, Map.fetch!(allowed_results, tool_use.id)}

        {:deny, reason} ->
          {tool_use.id, tool_use.name,
           {:error, Error.permission("Tool #{tool_use.name} blocked: #{reason}")}}
      end
    end)
  end

  @doc """
  Merge LLM response with tool results into new message list + enhanced tool blocks.

  Returns `{new_messages, enhanced_tool_blocks}`.
  """
  def merge_results(messages, response, results) do
    tool_use_blocks = Enum.filter(response.content, fn %{type: t} -> t == "tool_use" end)
    enhanced = merge_tool_results(tool_use_blocks, results)

    assistant_msg = %AIBrain.Message{
      role: "assistant",
      content: update_tool_blocks(response.content, enhanced)
    }

    {messages ++ [assistant_msg], enhanced}
  end

  @doc """
  Check turn count and wall-clock limits. Returns :continue or {:stop, reason}.
  """
  def check_limits(turn, max_turns, started_at, max_wall_time) do
    cond do
      turn >= max_turns ->
        {:stop, :max_turns_exceeded}

      DateTime.diff(DateTime.utc_now(), started_at, :second) >= max_wall_time ->
        {:stop, :wall_time_exceeded}

      true ->
        :continue
    end
  end

  @doc """
  Truncate and sanitize tool output before it is stored in run state.
  Truncation is now handled by Tool.Executor. This delegates to Result struct if available.
  """
  def truncate_tool_output(%Result{content: content}, _tool_name), do: content

  def truncate_tool_output(output, _tool_name) when is_binary(output) do
    if byte_size(output) > 10_000 do
      String.slice(output, 0, 10_000) <> "\n[truncated]"
    else
      output
    end
  end

  def truncate_tool_output(output, _tool_name), do: output

  defp merge_tool_results(tool_uses, results) do
    Enum.map(tool_uses, fn tool_use ->
      case Enum.find(results, fn {id, _, _} -> id == tool_use.id end) do
        {_, _, {:ok, %Result{} = result}} ->
          %{
            type: "tool_use",
            id: tool_use.id,
            name: tool_use.name,
            input: tool_use.input,
            status: "success",
            output: result.content,
            file_path: result.file_path,
            truncated: result.truncated,
            byte_size: result.byte_size
          }

        {_, _, {:error, %Error{} = err}} ->
          %{
            type: "tool_use",
            id: tool_use.id,
            name: tool_use.name,
            input: tool_use.input,
            status: "error",
            output: err.message,
            error_category: err.category,
            is_error: true
          }

        nil ->
          %{
            type: "tool_use",
            id: tool_use.id,
            name: tool_use.name,
            input: tool_use.input,
            status: "running"
          }
      end
    end)
  end

  defp update_tool_blocks(content, enhanced) do
    Enum.map(content, fn block ->
      case block do
        %{type: "tool_use", id: id} ->
          Enum.find(enhanced, fn tu -> tu.id == id end) || block

        _ ->
          block
      end
    end)
  end
end
