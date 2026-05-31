defmodule AIBrain.Context.Prepared do
  @moduledoc """
  Prepared context for query execution.

  ALL data normalized, ALL defaults resolved, NO mutation.
  """

  alias AIBrain.Context.Layers

  defstruct [
    :messages,
    :system_prompt,
    :requested_model,
    :tools
  ]

  @type t :: %__MODULE__{
          messages: list(map()),
          system_prompt: String.t(),
          requested_model: String.t() | nil,
          tools: list(map())
        }

  @doc """
  Build prepared context from raw messages and options.

  ALL defaults resolved here. NO more guessing downstream.
  """
  def build(raw_messages, opts) do
    normalized_opts = normalize_opts(opts)

    # Build system prompt using Layers module
    layers = Layers.build_all(raw_messages, normalized_opts)
    layers = AIBrain.Context.Deduplicator.deduplicate(layers)
    system_prompt = Layers.compose(layers, normalized_opts)

    # Extract tools
    tools = normalized_opts[:tools] || []

    %__MODULE__{
      messages: raw_messages,
      system_prompt: system_prompt,
      requested_model: normalized_opts[:model],
      tools: tools
    }
  end

  # ── Private ─────────────────────────────────────────────────────

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:tools, [])
    |> Keyword.put_new(:system, AIBrain.Prompts.identity())
    |> Keyword.put_new(:context, %{})
    |> Keyword.put_new(:max_turns, 200)
  end
end
