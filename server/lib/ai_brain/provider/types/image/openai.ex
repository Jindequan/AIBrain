defmodule AIBrain.Provider.Types.Image.OpenAI do
  @moduledoc """
  OpenAI DALL-E image generation backend.

  Generates images via the `POST /v1/images/generations` endpoint using the
  provider's OpenAI-compatible API key (Bearer token auth).
  """

  @behaviour AIBrain.Provider.Types.Image

  require Logger

  @impl true
  def generate(provider, prompt, opts \\ []) do
    base_url = provider.base_url
    api_key = provider.api_key

    if is_nil(base_url) or is_nil(api_key) do
      {:error, "Provider not configured for OpenAI image generation"}
    else
      do_generate(base_url, api_key, prompt, opts)
    end
  end

  defp do_generate(base_url, api_key, prompt, opts) do
    url = String.trim_trailing(base_url, "/") <> "/images/generations"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    body = %{
      "model" => opts[:model] || "dall-e-3",
      "prompt" => prompt,
      "n" => opts[:n] || 1,
      "size" => opts[:size] || "1024x1024",
      "response_format" => "b64_json"
    }

    Logger.info("DALL-E request: model=#{body["model"]} size=#{body["size"]} n=#{body["n"]}")

    case Req.post(url, headers: headers, json: body, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"data" => [%{"b64_json" => b64} | _]}}} ->
        {:ok, b64}

      {:ok, %{status: 200, body: %{"data" => [%{"url" => url} | _]}}} ->
        {:ok, url}

      {:ok, %{status: status, body: resp_body}} ->
        error_msg = extract_error(resp_body)
        {:error, "DALL-E API error (HTTP #{status}): #{error_msg}"}

      {:error, reason} ->
        {:error, "DALL-E API request failed: #{Exception.message(reason)}"}
    end
  end

  defp extract_error(%{"error" => %{"code" => code, "message" => msg}}), do: "#{code}: #{msg}"
  defp extract_error(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error(%{"error" => err}) when is_binary(err), do: err
  defp extract_error(%{"error" => _}), do: "unknown error"
  defp extract_error(_), do: "unknown error"
end
