defmodule AIBrain.Business.WebSearch do
  @moduledoc """
  Unified web search business layer.

  Tries providers in priority order: SearXNG → Brave → DuckDuckGo.
  Returns the first successful result set.

  The Tool layer should call `search/2` — never call provider clients directly.
  """

  alias AIBrain.Business.WebSearch.{SearXNG, Brave, DuckDuckGo}

  @doc """
  Search the web, trying providers in fallback order.

  Returns `{:ok, results, source}` where source is the provider atom,
  or `{:error, reason}` if all providers fail.
  """
  def search(query, num_results \\ 10) do
    with {:error, _} <- SearXNG.search(query, num_results),
         {:error, _} <- Brave.search(query, num_results) do
      DuckDuckGo.search(query, num_results)
    else
      {:ok, _results, _source} = success -> success
    end
  end
end
