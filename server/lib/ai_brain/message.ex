defmodule AIBrain.Message do
  @moduledoc """
  Internal message struct for all AIBrain communication.

  All internal code uses this struct. Protocol-specific format conversion
  happens at the boundary (Client.stream etc.).

  ## Fields

    * `id` - unique message identifier
    * `role` - "user", "assistant", "tool", or "system"
    * `content` - list of content blocks, always a list:
      - `%{type: "text", text: "..."}`
      - `%{type: "thinking", text: "...", signature: nil}`
      - `%{type: "tool_use", id: "...", name: "...", input: %{}}`
      - `%{type: "tool_result", tool_use_id: "...", content: "...", is_error: false}`
      - Future: `image`, `audio`, `file`, `link`, `agent`, `skill`...
    * `name` - source identifier (tool name, agent name, skill name)
    * `metadata` - extensible key-value store
    * `created_at` - ISO8601 timestamp of message creation
  """

  defstruct [id: nil, role: nil, content: [], name: nil, metadata: %{}, created_at: nil]

  @type role :: String.t()
  @type block :: map()
  @type t :: %__MODULE__{
          id: String.t() | nil,
          role: role(),
          content: [block()],
          name: String.t() | nil,
          metadata: map(),
          created_at: String.t() | nil
        }

  @doc "Build a new Message"
  def new(role, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      role: role,
      content: Keyword.get(opts, :content, []),
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata, %{}),
      created_at: Keyword.get(opts, :created_at) || now_iso()
    }
  end

  @doc "Parse from JSON-parsed map (string keys)"
  def from_json(map) when is_map(map) do
    %__MODULE__{
      id: Map.get(map, "id") || Map.get(map, :id),
      role: Map.get(map, "role") || Map.get(map, :role),
      content: normalize_content(Map.get(map, "content") || Map.get(map, :content) || []),
      name: Map.get(map, "name") || Map.get(map, :name),
      metadata: Map.get(map, "metadata") || Map.get(map, :metadata) || %{},
      created_at: Map.get(map, "created_at") || Map.get(map, :created_at) || now_iso()
    }
  end

  @doc "Returns current UTC time as ISO8601 string"
  def now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  # Normalize content to a list of blocks
  defp normalize_content(content) when is_list(content), do: content

  defp normalize_content(content) when is_binary(content) and content != "",
    do: [%{type: "text", text: content}]

  defp normalize_content(_content), do: []

  defp generate_id do
    "msg_#{System.unique_integer([:positive])}"
  end
end

defimpl Jason.Encoder, for: AIBrain.Message do
  def encode(%AIBrain.Message{} = msg, opts) do
    Jason.Encode.map(
      %{
        id: msg.id,
        role: msg.role,
        content: msg.content,
        name: msg.name,
        metadata: msg.metadata,
        created_at: msg.created_at
      },
      opts
    )
  end
end
