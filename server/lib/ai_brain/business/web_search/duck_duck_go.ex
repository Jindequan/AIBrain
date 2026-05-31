defmodule AIBrain.Business.WebSearch.DuckDuckGo do
  @moduledoc """
  DuckDuckGo HTML search client (fallback, no API key required).

  Scrapes the HTML results page — fragile but always available as last resort.
  """

  @html_url "https://html.duckduckgo.com/html/"

  def search(query, num_results) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"}
    ]

    case Req.post(@html_url, form: [q: query], headers: headers, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: html}} when is_binary(html) ->
        results = parse_html(html, num_results)

        if results == [] do
          {:error, "DuckDuckGo returned no parseable results"}
        else
          {:ok, results, "duckduckgo"}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "DuckDuckGo HTTP #{status}"}

      {:error, reason} ->
        {:error, "DuckDuckGo network error: #{inspect(reason)}"}
    end
  end

  # -- HTML Parsing --

  defp parse_html(html, num_results) do
    html
    |> String.split(~r/<div[^>]*class="result[^"]*"[^>]*>/i)
    |> Enum.slice(1, num_results)
    |> Enum.map(&extract_result/1)
    |> Enum.filter(& &1)
  end

  defp extract_result(html) do
    title = extract_text(html, ~r/<a[^>]*class="result__a"[^>]*>(.*?)<\/a>/is)
    url = extract_attr(html, ~r/<a[^>]*class="result__a"[^>]*href="([^"]*)"/is)
    snippet = extract_text(html, ~r/<a[^>]*class="result__snippet"[^>]*>(.*?)<\/a>/is)

    if title && url do
      %{
        "title" => String.trim(title),
        "url" => decode_url(url),
        "snippet" => String.trim(snippet || "")
      }
    end
  end

  defp extract_text(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [text] ->
        text
        |> HtmlEntities.decode()
        |> String.split(~r/<[^>]*>/)
        |> Enum.join("")
        |> String.trim()

      _ ->
        nil
    end
  end

  defp extract_attr(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end

  defp decode_url(url) do
    if String.contains?(url, "/l/?uddg=") do
      case Regex.run(~r/uddg=([^&"]+)/, url) do
        [_, encoded] ->
          try do
            URI.decode(encoded)
          rescue
            _ -> url
          end

        _ ->
          url
      end
    else
      url
    end
  end
end
