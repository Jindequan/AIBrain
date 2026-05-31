defmodule AIBrain.Business.WebSearch.Brave do
  @moduledoc """
  Brave Search API client.

  Expects BRAVE_API_KEY environment variable to be set.
  """

  @env_key "BRAVE_API_KEY"
  @api_url "https://api.search.brave.com/res/v1/web/search"

  def search(query, num_results) do
    case System.get_env(@env_key) do
      nil ->
        {:error, :not_configured}

      api_key ->
        headers = [
          {"Accept", "application/json"},
          {"Accept-Encoding", "gzip"},
          {"X-Subscription-Token", api_key}
        ]

        params = [q: query, count: min(num_results, 20)]

        case Req.get(@api_url, headers: headers, params: params, receive_timeout: 10_000) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            results =
              (get_in(body, ["web", "results"]) || [])
              |> Enum.take(num_results)
              |> Enum.map(&format_result/1)

            {:ok, results, "brave"}

          {:ok, %Req.Response{status: 429}} ->
            {:error, "Brave rate limited"}

          {:ok, %Req.Response{status: status}} ->
            {:error, "Brave HTTP #{status}"}

          {:error, reason} ->
            {:error, inspect(reason)}
        end
    end
  end

  defp format_result(r) do
    %{
      "title" => r["title"] || "",
      "url" => r["url"] || "",
      "snippet" => r["description"] || ""
    }
  end
end
