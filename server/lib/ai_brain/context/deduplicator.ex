defmodule AIBrain.Context.Deduplicator do
  @moduledoc """
  Detects and removes duplicate information across context layers.

  Prevents the same knowledge from appearing multiple times in the
  system prompt when it exists in both KnowledgeWiki and RAG.
  """

  @doc """
  Remove duplicate sentences across knowledge and task layers.

  Strategy: if the same fact appears in both KnowledgeWiki (from past sessions)
  and the current task context, prefer the KnowledgeWiki version (it has been
  confirmed over multiple interactions).
  """
  def deduplicate(layers) when is_map(layers) do
    knowledge = Map.get(layers, :knowledge) || ""
    task = Map.get(layers, :task) || ""

    if knowledge == "" or task == "" do
      layers
    else
      cleaned_knowledge = remove_overlaps(knowledge, task)
      Map.put(layers, :knowledge, cleaned_knowledge)
    end
  end

  # Simple sentence-based dedup: check if knowledge sentences appear in task context
  defp remove_overlaps(knowledge, task) do
    task_lower = String.downcase(task)
    knowledge_sentences = split_into_sentences(knowledge)

    # Keep sentences whose core content (>= 15 chars) doesn't appear in the task layer
    knowledge_sentences
    |> Enum.reject(fn sentence ->
      trimmed = String.trim(sentence)

      if String.length(trimmed) < 15 do
        false
      else
        normalized =
          trimmed |> String.downcase() |> String.slice(0..min(String.length(trimmed), 60))

        String.contains?(task_lower, normalized)
      end
    end)
    |> Enum.join("\n")
  end

  defp split_into_sentences(text) when is_binary(text) do
    text
    |> String.split(~r/(?<=[.!?。！？\n])\s+/)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_into_sentences(_), do: []
end
