defmodule AIBrain.Tool.Result do
  @moduledoc """
  Structured tool output with truncation metadata and error tracking.

  `content` is what the LLM sees — either full output or a summary.
  `metadata` carries tool-specific structured data for evidence/UI.
  `file_path` is set when full output was written to FileStore.
  `error_category` is nil on success; set to a Tool.Error category string on failure.
  """

  @type t :: %__MODULE__{
          content: String.t(),
          summary: String.t() | nil,
          file_path: String.t() | nil,
          truncated: boolean(),
          byte_size: non_neg_integer(),
          success: boolean(),
          error_category: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :content,
    :summary,
    :file_path,
    truncated: false,
    byte_size: 0,
    success: true,
    error_category: nil,
    metadata: %{}
  ]

  @doc "Build a successful result with structured metadata."
  def ok(content, metadata \\ %{}) when is_map(metadata) do
    %__MODULE__{
      content: content,
      success: true,
      byte_size: byte_size(content),
      metadata: metadata
    }
  end

  @doc "Build a failed result with an error category."
  def error(message, error_category, metadata \\ %{}) when is_binary(error_category) do
    %__MODULE__{
      content: message,
      success: false,
      error_category: error_category,
      byte_size: byte_size(message),
      metadata: metadata
    }
  end

  @doc """
  Split lines into head + tail with overlap protection.

  Returns `{:full, lines}` when total lines <= head + tail (no split needed).
  Returns `{:split, head_lines, tail_lines, skipped_count}` otherwise.
  """
  @spec head_tail([String.t()], keyword()) ::
          {:full, [String.t()]} | {:split, [String.t()], [String.t()], non_neg_integer()}
  def head_tail(lines, opts \\ []) do
    head_n = Keyword.get(opts, :head, 20)
    tail_n = Keyword.get(opts, :tail, 20)
    total = length(lines)

    if total <= head_n + tail_n do
      {:full, lines}
    else
      {:split, Enum.take(lines, head_n), Enum.take(lines, -tail_n), total - head_n - tail_n}
    end
  end
end
