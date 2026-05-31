defmodule AIBrain.Session.HistoryMerge do
  @moduledoc """
  Merges persisted conversation history with the current inbound messages.

  Chat entrypoints persist the user's message before starting the run so the
  UI can update immediately. The runtime must therefore treat the current
  request as an overlap candidate instead of blindly appending it again.
  """

  def merge(history, new_messages) when is_list(history) and is_list(new_messages) do
    overlap = longest_overlap(history, new_messages)
    history ++ Enum.drop(new_messages, overlap)
  end

  defp longest_overlap(_history, []), do: 0
  defp longest_overlap([], _new_messages), do: 0

  defp longest_overlap(history, new_messages) do
    max_overlap = min(length(history), length(new_messages))

    max_overlap..1//-1
    |> Enum.find(0, fn size ->
      history
      |> Enum.take(-size)
      |> same_messages?(Enum.take(new_messages, size))
    end)
  end

  defp same_messages?(left, right) do
    Enum.map(left, &signature/1) == Enum.map(right, &signature/1)
  end

  defp signature(message) do
    {read(message, :role), content_signature(read(message, :content))}
  end

  defp read(%AIBrain.Message{} = message, key), do: Map.get(message, key)

  defp read(message, key) when is_map(message),
    do: Map.get(message, key) || Map.get(message, Atom.to_string(key))

  defp read(_message, _key), do: nil

  defp content_signature(content) when is_binary(content), do: String.trim(content)

  defp content_signature(content) when is_list(content) do
    if text_only?(content) do
      content
      |> Enum.map_join("\n\n", fn block -> String.trim(to_string(read(block, :text) || "")) end)
      |> String.trim()
    else
      Enum.map(content, fn block ->
        type = read(block, :type)

        case type do
          "text" -> {"text", String.trim(to_string(read(block, :text) || ""))}
          "thinking" -> {"thinking", String.trim(to_string(read(block, :text) || ""))}
          "tool_use" -> {"tool_use", read(block, :id), read(block, :name), read(block, :input)}
          "tool_result" -> {"tool_result", read(block, :tool_use_id), read(block, :content)}
          _ -> normalize_map(block)
        end
      end)
    end
  end

  defp content_signature(content), do: content

  defp text_only?([]), do: false
  defp text_only?(blocks), do: Enum.all?(blocks, &(read(&1, :type) == "text"))

  defp normalize_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {key, _value} ->
      key in [:id, "id", :created_at, "created_at", :metadata, "metadata"]
    end)
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp normalize_map(value), do: value
end
