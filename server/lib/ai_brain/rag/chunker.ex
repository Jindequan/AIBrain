defmodule AIBrain.RAG.Chunker do
  @moduledoc """
  Splits documents into chunks for embedding and retrieval.

  Uses a simple recursive character splitter with configurable
  chunk size and overlap.
  """

  @default_chunk_size 1000
  @default_overlap 200

  @doc """
  Split text into chunks of approximate size with overlap.

  Returns list of %{text: binary, index: integer, metadata: map}.
  """
  def chunk(text, opts \\ []) when is_binary(text) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    text
    |> split_into_chunks(chunk_size, overlap)
    |> Enum.with_index(0)
    |> Enum.map(fn {chunk_text, i} ->
      %{text: chunk_text, index: i, metadata: %{}}
    end)
  end

  defp split_into_chunks(text, chunk_size, overlap) do
    # First, split by double newlines (paragraphs)
    paragraphs = String.split(text, ~r{\n\n+})

    # Group paragraphs into chunks of roughly chunk_size characters
    merge_paragraphs(paragraphs, chunk_size, overlap, [])
  end

  defp merge_paragraphs([], _chunk_size, _overlap, acc), do: Enum.reverse(acc)

  defp merge_paragraphs(paragraphs, chunk_size, overlap, acc) do
    {chunk, rest} = take_chunk(paragraphs, chunk_size, [])

    # Get overlap: take last paragraphs from the chunk
    overlap_text =
      if overlap > 0 and rest != [] do
        chunk
        |> Enum.reverse()
        |> take_overlap(overlap, [])
        |> Enum.reverse()
        |> Enum.join("\n\n")
        |> then(fn t -> if t == "", do: [], else: [t] end)
      else
        []
      end

    rest = overlap_text ++ rest
    merge_paragraphs(rest, chunk_size, overlap, [Enum.join(chunk, "\n\n") | acc])
  end

  defp take_chunk([], _size, acc), do: {Enum.reverse(acc), []}

  defp take_chunk([p | rest], size, acc) do
    current_size =
      Enum.reduce(acc, 0, fn s, total -> total + String.length(s) end) +
        String.length(p) +
        length(acc) * 2

    if current_size <= size do
      take_chunk(rest, size, [p | acc])
    else
      {Enum.reverse(acc), [p | rest]}
    end
  end

  defp take_overlap(_list, 0, acc), do: acc

  defp take_overlap([], _remaining, acc), do: acc

  defp take_overlap([item | rest], remaining_overlap, acc) do
    char_len = String.length(item)
    take_overlap(rest, max(0, remaining_overlap - char_len), [item | acc])
  end
end
