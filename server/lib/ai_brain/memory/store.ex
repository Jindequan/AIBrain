defmodule AIBrain.Memory.Store do
  @moduledoc """
  Behaviour for memory storage backends.

  Each backend (KnowledgeWiki, RAG, Session, Workspace) implements this
  behaviour so the Memory.Manager can query them uniformly.
  """

  alias AIBrain.Memory.Entry

  @callback search(query :: String.t(), opts :: keyword()) :: [Entry.t()]
  @callback count() :: integer()
  @callback source() :: Entry.source()
end
