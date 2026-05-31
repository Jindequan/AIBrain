defmodule AIBrain.Channel.Reply do
  @moduledoc """
  Builds a stable reply envelope for surfaced channel responses.
  """

  def build(surface, content, metadata \\ %{}) when is_binary(content) and is_map(metadata) do
    %{
      role: "assistant",
      content: content,
      metadata:
        metadata
        |> Map.put(:surface, surface)
        |> Map.put_new(:kind, :channel_reply)
        |> Map.put_new(:schema_version, 1)
    }
  end
end
