defmodule AIBrain.Business.WebSearch.SearXNG do
  @moduledoc """
  SearXNG search client (self-hosted, recommended).

  Expects SEARXNG_URL environment variable to be set.
  """

  @env_key "SEARXNG_URL"

  def search(query, num_results) do
    case System.get_env(@env_key) do
      nil ->
        {:error, :not_configured}

      base_url ->
        url = base_url <> "/search"
        params = [q: query, format: "json", engines: "google,bing,duckduckgo", pageno: 1]

        case Req.get(url, params: params, receive_timeout: 10_000) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            results =
              (body["results"] || [])
              |> Enum.take(num_results)
              |> Enum.map(&format_result/1)

            {:ok, results, "searxng"}

          {:ok, %Req.Response{status: status}} ->
            {:error, "SearXNG HTTP #{status}"}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
    end
  end

  defp format_result(r) do
    %{
      "title" => r["title"] || "",
      "url" => r["url"] || "",
      "snippet" => r["content"] || ""
    }
  end
end
