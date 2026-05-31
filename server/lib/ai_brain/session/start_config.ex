defmodule AIBrain.Session.StartConfig do
  @moduledoc """
  Session start configuration - explicit structure, NO guessing.

  Replaces scattered Keyword.get(opts, ...) calls.
  """

  defstruct [
    :session_id,
    :messages,
    :requested_model,
    :workspace_path,
    :session_type,
    :channel_adapter,
    :channel_id,
    :capabilities
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          messages: list(map()),
          requested_model: String.t() | nil,
          workspace_path: String.t() | nil,
          session_type: String.t(),
          channel_adapter: atom() | nil,
          channel_id: String.t() | nil,
          capabilities: map()
        }

  @doc """
  Build start config from options.

  ALL defaults resolved here. NO more Keyword.get downstream.
  """
  def build(session_id, messages, requested_model, opts) do
    capabilities = extract_capabilities(opts)

    %__MODULE__{
      session_id: session_id,
      messages: messages,
      requested_model: requested_model,
      workspace_path: Keyword.get(opts, :workspace_path),
      session_type: Keyword.get(opts, :session_type, "manual"),
      channel_adapter: Keyword.get(opts, :channel_adapter),
      channel_id: Keyword.get(opts, :channel_id),
      capabilities: capabilities
    }
  end

  @doc """
  Convert to format expected by Memory.start_session/3.
  """
  def to_memory_format(%__MODULE__{} = config) do
    metadata = build_metadata(config)

    [
      messages: config.messages,
      requested_model: config.requested_model,
      workspace_path: config.workspace_path,
      metadata: metadata
    ]
  end

  # ── Private ─────────────────────────────────────────────────────

  defp extract_capabilities(opts) do
    case Keyword.get(opts, :capability_summary) do
      nil -> %{enabled: [], rejected: []}
      caps -> caps
    end
  end

  defp build_metadata(%__MODULE__{} = config) do
    %{
      session_type: config.session_type,
      channel_adapter: config.channel_adapter,
      channel_id: config.channel_id,
      capabilities: config.capabilities
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
