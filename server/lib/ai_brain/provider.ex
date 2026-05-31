defmodule AIBrain.Provider do
  @moduledoc """
  Facade module for provider-related operations.

  Delegates to `AIBrain.Provider.Registry` for data access.
  """

  @doc """
  Returns all providers from the Registry.
  """
  defdelegate list(), to: AIBrain.Provider.Registry, as: :list

  @doc """
  Returns a single provider by name.
  """
  defdelegate get(name), to: AIBrain.Provider.Registry, as: :get

  @doc """
  Returns all active LLM providers (those with an "openai" protocol endpoint),
  sorted by priority.
  """
  def active_llm() do
    list()
    |> Enum.filter(fn p -> p.enabled and (p.chat_url || p.base_url) end)
    |> Enum.sort_by(& &1.priority)
  end

  @doc """
  Return providers by capability type.

  The current provider config is LLM-first; image/music provider structs live in
  their own modules and are not stored in the unified registry yet.
  """
  def list_by_type(type) when type in [:llm, "llm", :chat, "chat"], do: active_llm()
  def list_by_type(_type), do: []
end
