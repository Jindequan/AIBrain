defmodule AIBrain.Business.WebContent.PageFetcher do
  @moduledoc """
  HTTP page fetcher with proper headers and redirect following.
  """

  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  @doc """
  Fetch a web page, following redirects.

  Returns `{:ok, %{html: String.t(), final_url: String.t()}}` or `{:error, reason}`.
  """
  def fetch(url) do
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"}
    ]

    case Req.get(url, headers: headers, redirect: :follow) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %{html: body, final_url: url}}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %Mint.TransportError{reason: reason}} ->
        {:error, "Network error: #{reason}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end
end
