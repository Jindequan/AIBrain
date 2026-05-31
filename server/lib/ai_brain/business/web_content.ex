defmodule AIBrain.Business.WebContent do
  @moduledoc """
  Unified web content fetching business layer.

  Provides URL validation (SSRF protection), page fetching,
  content extraction, and format conversion.

  The Tool layer should call these functions — never use internal modules directly.
  """

  alias AIBrain.Business.WebContent.{UrlValidator, PageFetcher, ContentExtractor}

  @doc """
  Fetch a web page and extract its content.

  Returns `{:ok, %{"url", "title", "content", "format", "content_length"}}`
  or `{:error, reason}`.
  """
  def fetch_and_extract(url, format \\ "text") do
    with :ok <- UrlValidator.validate(url),
         {:ok, %{html: html, final_url: final_url}} <- PageFetcher.fetch(url) do
      title = ContentExtractor.extract_title(html)
      content = ContentExtractor.extract(html, format)

      {:ok,
       %{
         "url" => final_url,
         "title" => title,
         "content" => content,
         "format" => format,
         "content_length" => String.length(content)
       }}
    end
  end
end
