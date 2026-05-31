defmodule AIBrain.LLM.SSE.Parser do
  @moduledoc """
  SSE event parser extracted from the LLM loop.

  Collects and parses Server-Sent Events from LLM streaming responses.
  """

  require Logger

  def collect_sse_events(events) do
    result =
      Enum.reduce(
        events,
        %{
          text: "",
          tool_uses: [],
          content: [],
          stop_reason: nil,
          tool_bufs: %{},
          thinking_bufs: %{},
          text_buf: "",
          events: []
        },
        fn event, acc ->
          case event do
            {:text_delta, t} ->
              %{acc | text: acc.text <> t, text_buf: acc.text_buf <> t}

            {:thinking_start, index} ->
              acc = flush_text_buf(acc)
              thinking_bufs = Map.put_new(acc.thinking_bufs, index, "")
              %{acc | thinking_bufs: thinking_bufs}

            {:thinking_delta, index, text} ->
              thinking_bufs =
                Map.update(acc.thinking_bufs, index, text, fn existing -> existing <> text end)

              %{acc | thinking_bufs: thinking_bufs}

            {:tool_use_start, %{index: index, id: id, name: name}} ->
              acc = flush_text_buf(acc)
              tool_bufs = Map.put(acc.tool_bufs, index, %{id: id, name: name, json: ""})
              %{acc | tool_bufs: tool_bufs}

            {:tool_input_delta, %{index: index, chunk: chunk}} ->
              tool_bufs =
                Map.update(acc.tool_bufs, index, %{id: nil, name: nil, json: chunk}, fn buf ->
                  %{buf | json: buf.json <> chunk}
                end)

              %{acc | tool_bufs: tool_bufs}

            {:content_block_stop, index} ->
              {thinking_text, thinking_bufs} = Map.pop(acc.thinking_bufs, index)
              {tool_data, tool_bufs} = Map.pop(acc.tool_bufs, index)

              acc = flush_text_buf(acc)

              cond do
                thinking_text ->
                  block = %{type: "thinking", text: thinking_text, thinking_index: index}
                  %{acc | thinking_bufs: thinking_bufs, content: acc.content ++ [block]}

                tool_data ->
                  %{id: id, name: name, json: json} = tool_data

                  input =
                    case Jason.decode(json) do
                      {:ok, decoded} -> decoded
                      {:error, _} -> %{"_raw" => json}
                    end

                  tool = %{id: id, name: name, input: input}
                  tool_block = %{type: "tool_use", id: id, name: name, input: input}

                  %{
                    acc
                    | tool_bufs: tool_bufs,
                      tool_uses: acc.tool_uses ++ [tool],
                      content: acc.content ++ [tool_block],
                      events:
                        acc.events ++ [{:tool_use_complete, %{id: id, name: name, input: input}}]
                  }

                true ->
                  acc
              end

            {:stop, reason} ->
              text_block =
                if acc.text_buf != "" do
                  [%{type: "text", text: acc.text_buf}]
                else
                  []
                end

              {thinking_blocks, thinking_bufs} = do_finalize_thinking(acc.thinking_bufs)
              {finalized, tool_events} = do_finalize_tools(acc.tool_bufs)

              # When the model only produced thinking (no visible text), use the
              # thinking content as the output text so runs don't complete blank.
              acc_text =
                if acc.text == "" and thinking_blocks != [] do
                  thinking_text = thinking_blocks |> Enum.map_join("\n", & &1.text) |> String.trim()
                  if thinking_text != "", do: thinking_text, else: acc.text
                else
                  acc.text
                end

              %{
                acc
                | text: acc_text,
                  thinking_bufs: thinking_bufs,
                  tool_bufs: %{},
                  tool_uses: acc.tool_uses ++ finalized,
                  content:
                    acc.content ++
                      thinking_blocks ++
                      Enum.map(finalized, fn t ->
                        %{type: "tool_use", id: t.id, name: t.name, input: t.input}
                      end) ++
                      text_block,
                  events: acc.events ++ tool_events,
                  text_buf: "",
                  stop_reason: normalize_stop_reason(reason)
              }

            {:error, error_event} ->
              Logger.error("LLM API error event during stream: #{inspect(error_event)}")
              %{acc | stop_reason: :error}

            _ ->
              acc
          end
        end
      )

    %{result | events: Enum.reverse(result.events)}
  end

  def normalize_stop_reason(reason) when reason in ~w(tool_use tool_calls), do: :tool_call
  def normalize_stop_reason(reason) when reason in ~w(stop end_turn), do: :stop
  def normalize_stop_reason(reason) when reason in ~w(max_tokens length), do: :max_tokens
  def normalize_stop_reason(_reason), do: :stop

  defp do_finalize_tools(tool_bufs) when tool_bufs == %{}, do: {[], []}

  defp do_finalize_tools(tool_bufs) do
    finalized =
      Enum.map(tool_bufs, fn {_index, %{id: id, name: name, json: json}} ->
        input =
          case Jason.decode(json) do
            {:ok, decoded} -> decoded
            {:error, _} -> %{"_raw" => json}
          end

        %{id: id, name: name, input: input}
      end)

    events =
      Enum.map(finalized, fn %{id: id, name: name, input: input} ->
        {:tool_use_complete, %{id: id, name: name, input: input}}
      end)

    {finalized, events}
  end

  defp do_finalize_thinking(thinking_bufs) when thinking_bufs == %{}, do: {[], %{}}

  defp do_finalize_thinking(thinking_bufs) do
    blocks =
      Enum.map(thinking_bufs, fn {index, text} ->
        %{type: "thinking", text: text, thinking_index: index}
      end)

    {blocks, %{}}
  end

  defp flush_text_buf(%{text_buf: ""} = acc), do: acc

  defp flush_text_buf(acc) do
    %{acc | content: acc.content ++ [%{type: "text", text: acc.text_buf}], text_buf: ""}
  end
end
