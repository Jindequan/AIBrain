defmodule AIBrain.Memory.Query do
  @moduledoc """
  Memory query - explicit structure, NO guessing.

  Replaces scattered Keyword.get(opts, ...) calls.
  """

  defstruct [
    :text,
    :limit,
    :sources,
    :type,
    :session_id
  ]

  @type t :: %__MODULE__{
          text: String.t(),
          limit: pos_integer(),
          sources: list(atom()) | nil,
          type: String.t() | nil,
          session_id: String.t() | nil
        }

  @doc """
  Build query from input.
  """
  def build(text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    sources = Keyword.get(opts, :sources)
    type = Keyword.get(opts, :type)
    session_id = Keyword.get(opts, :session_id)

    %__MODULE__{
      text: text,
      limit: limit,
      sources: sources,
      type: type,
      session_id: session_id
    }
  end

  @doc """
  Validate query.
  """
  def validate(%__MODULE__{} = query) do
    cond do
      is_binary(query.text) and query.text != "" -> :ok
      true -> {:error, :missing_text}
    end
  end

  @doc """
  Convert to keyword list for backward compatibility.
  """
  def to_opts(%__MODULE__{} = query) do
    []
    |> put_if_not_nil(:limit, query.limit)
    |> put_if_not_nil(:sources, query.sources)
    |> put_if_not_nil(:type, query.type)
    |> put_if_not_nil(:session_id, query.session_id)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp put_if_not_nil(opts, _key, nil), do: opts
  defp put_if_not_nil(opts, key, value), do: Keyword.put(opts, key, value)
end
