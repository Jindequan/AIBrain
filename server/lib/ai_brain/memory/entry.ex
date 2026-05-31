defmodule AIBrain.Memory.Entry do
  @moduledoc """
  Unified memory entry across all storage backends.

  Each store adapter normalizes its native format into this struct
  so the Memory.Manager can rank, dedup, and fuse results uniformly.
  """

  @type source :: :knowledge_wiki | :rag | :session | :workspace
  @type entry_type :: :fact | :preference | :learning | :task_outcome | :document | :conversation

  defstruct [
    :id,
    :source,
    :type,
    :content,
    :content_hash,
    :embedding,
    :confidence,
    :decay_score,
    :created_at,
    :tags,
    :metadata
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          source: source(),
          type: entry_type(),
          content: String.t(),
          content_hash: String.t() | nil,
          embedding: binary() | nil,
          confidence: float(),
          decay_score: float(),
          created_at: String.t() | nil,
          tags: [String.t()],
          metadata: map()
        }

  def new(attrs) when is_map(attrs) do
    struct!(__MODULE__, Map.merge(defaults(), Map.delete(attrs, :__struct__)))
  end

  defp defaults do
    %{
      confidence: 0.5,
      decay_score: 1.0,
      tags: [],
      metadata: %{}
    }
  end

  @doc "Generate a content hash for deduplication."
  def hash_content(content) when is_binary(content) do
    :crypto.hash(:sha256, String.downcase(String.trim(content)))
    |> Base.encode16(case: :lower)
  end
end
