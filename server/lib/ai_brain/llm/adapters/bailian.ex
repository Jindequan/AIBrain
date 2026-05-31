defmodule AIBrain.LLM.Adapters.Bailian do
  @moduledoc """
  Bailian (百炼/DashScope) provider adapter.

  Uses OpenAI protocol format. The Deepseek models served through
  DashScope require `reasoning_content` for thinking mode — this adapter
  extends the base OpenAI protocol with reasoning_content handling.
  """

  @default_max_tokens 8096

  def url_path, do: "/v1/chat/completions"

  def headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  def build_body(provider, messages, tools, opts) do
    api_messages = Enum.map(messages, &convert_message/1)

    all_messages =
      case opts[:system] do
        nil -> api_messages
        "" -> api_messages
        sys -> [%{role: "system", content: sys} | api_messages]
      end

    model = resolve_model(provider, opts[:model])

    %{
      "model" => model,
      "max_tokens" => opts[:max_tokens] || @default_max_tokens,
      "stream" => true,
      "messages" => all_messages,
      "tools" => to_openai_tools(tools)
    }
  end

  def parse_sse_line("data: [DONE]"), do: :skip

  def parse_sse_line("data: " <> json) do
    case Jason.decode(json) do
      {:ok, decoded} -> classify_events(decoded)
      _ -> :skip
    end
  end

  def parse_sse_line("data:" <> json) do
    case Jason.decode(json) do
      {:ok, decoded} -> classify_events(decoded)
      _ -> :skip
    end
  end

  def parse_sse_line(_line), do: :skip

  def convert_message(%{role: "assistant", content: content}) do
    blocks = normalize_msg_content(content)
    text = find_block(blocks, "text")
    thinking = find_block(blocks, "thinking")

    tool_uses =
      Enum.filter(
        blocks,
        &(Map.get(&1, :type) == "tool_use" || Map.get(&1, "type") == "tool_use")
      )

    base = %{role: "assistant", content: text[:text] || text["text"] || ""}

    base =
      if thinking != %{} do
        Map.put(base, :reasoning_content, thinking[:text] || thinking["text"])
      else
        base
      end

    if tool_uses != [] do
      tc =
        Enum.map(tool_uses, fn tu ->
          id = tu[:id] || tu["id"]
          name = tu[:name] || tu["name"]
          input = tu[:input] || tu["input"] || %{}

          %{
            id: id,
            type: "function",
            function: %{name: name, arguments: Jason.encode!(input)}
          }
        end)

      Map.put(base, :tool_calls, tc)
    else
      base
    end
  end

  def convert_message(msg), do: AIBrain.LLM.Adapters.Protocol.OpenAI.convert_message(msg)

  defp classify_events(%{"choices" => choices}) do
    choice = List.first(choices) || %{}
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]

    events =
      []
      |> add_text(delta)
      |> add_reasoning(delta)
      |> add_tool_calls(delta)
      |> add_finish(finish_reason)

    if events == [], do: :skip, else: events
  end

  defp classify_events(%{"error" => error}) do
    [{:sse_error, error}]
  end

  defp classify_events(_event), do: :skip

  defp add_text(events, %{"content" => content}) when is_binary(content) and content != "" do
    events ++ [{:text_delta, content}]
  end

  defp add_text(events, _delta), do: events

  # Bailian reasoning_content in SSE responses (DashScope Deepseek models)
  # Track thinking state in process dict to avoid emitting thinking_start for every delta chunk
  defp add_reasoning(events, %{"reasoning_content" => rc}) when is_binary(rc) and rc != "" do
    key = {:bailian_thinking_started, self()}
    started? = Process.get(key, false)

    if started? do
      events ++ [{:thinking_delta, 0, rc}]
    else
      Process.put(key, true)
      events ++ [{:thinking_start, 0}, {:thinking_delta, 0, rc}]
    end
  end

  defp add_reasoning(events, _delta), do: events

  defp add_tool_calls(events, %{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.reduce(tool_calls, events, fn tc, acc ->
      index = tc["index"]
      acc = add_tool_start(acc, tc, index)
      add_tool_args(acc, tc, index)
    end)
  end

  defp add_tool_calls(events, _delta), do: events

  defp add_tool_start(events, %{"id" => id} = tc, index) when is_binary(id) and id != "" do
    name = get_in(tc, ["function", "name"]) || ""
    events ++ [{:tool_use_start, %{index: index, id: id, name: name}}]
  end

  defp add_tool_start(events, _tc, _index), do: events

  defp add_tool_args(events, tc, index) do
    case get_in(tc, ["function", "arguments"]) do
      args when is_binary(args) and args != "" ->
        events ++ [{:tool_input_delta, %{index: index, chunk: args}}]

      _ ->
        events
    end
  end

  defp add_finish(events, reason) when is_binary(reason) and reason != "" do
    # Clear thinking state when request completes
    Process.delete({:bailian_thinking_started, self()})
    events ++ [{:stop, reason}]
  end

  defp add_finish(events, _reason) do
    # Clear thinking state when request completes
    Process.delete({:bailian_thinking_started, self()})
    events
  end

  defp to_openai_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "function" => %{
          "name" => tool["name"],
          "description" => tool["description"],
          "parameters" => tool["input_schema"]
        }
      }
    end)
  end

  defp resolve_model(provider, requested_model) do
    AIBrain.Provider.Info.map_model(provider, requested_model || "default")
  end

  defp normalize_msg_content(content) when is_binary(content) and content != "",
    do: [%{type: "text", text: content}]

  defp normalize_msg_content(content) when is_binary(content), do: []
  defp normalize_msg_content(content), do: content

  defp find_block(blocks, type) do
    Enum.find(blocks, %{}, fn block ->
      Map.get(block, :type) == type || Map.get(block, "type") == type
    end)
  end
end
