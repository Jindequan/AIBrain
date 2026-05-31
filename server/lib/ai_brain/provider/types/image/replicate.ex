defmodule AIBrain.Provider.Types.Image.Replicate do
  @moduledoc """
  Replicate image generation backend.

  Generates images via the Replicate API by creating a prediction and polling
  until it completes. The provider's endpoint should have protocol "replicate"
  with an API key (Bearer token auth).

  See: https://replicate.com/docs/reference/http
  """

  @behaviour AIBrain.Provider.Types.Image

  require Logger

  @poll_interval_ms 1000
  @max_poll_attempts 120

  @impl true
  def generate(provider, prompt, opts \\ []) do
    base_url = provider.base_url
    api_key = provider.api_key

    if is_nil(base_url) or is_nil(api_key) do
      {:error, "Provider not configured for replicate"}
    else
      do_generate(base_url, api_key, prompt, opts)
    end
  end

  defp do_generate(base_url, api_key, prompt, opts) do
    base_url = String.trim_trailing(base_url, "/")

    version =
      opts[:model] || opts[:version] ||
        "db21e45d3f7023abc2a46ee38a23973f6dce16bb082a930b0c49861f96d1e5bf"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    # Step 1: Create a prediction
    prediction_url = base_url <> "/predictions"

    body = %{
      "version" => version,
      "input" => %{
        "prompt" => prompt
      }
    }

    Logger.info("Replicate create prediction: version=#{version}")

    case Req.post(prediction_url, headers: headers, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 201, body: %{"id" => id, "urls" => %{"get" => get_url}} = resp}} ->
        # Normalize polling URL
        poll_url = get_url || "#{base_url}/predictions/#{id}"
        poll_and_get_result(poll_url, headers, resp)

      {:ok, %{status: 201, body: %{"id" => id}}} ->
        poll_url = "#{base_url}/predictions/#{id}"
        poll_and_get_result(poll_url, headers, %{})

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "Replicate API error (HTTP #{status}): #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, "Replicate API request failed: #{Exception.message(reason)}"}
    end
  end

  defp poll_and_get_result(poll_url, headers, initial_resp) do
    # Check if already completed
    status = Map.get(initial_resp, "status")

    cond do
      status == "succeeded" ->
        extract_output(initial_resp)

      status == "failed" ->
        {:error, Map.get(initial_resp, "error", "Prediction failed")}

      status == "canceled" ->
        {:error, "Prediction was canceled"}

      true ->
        do_poll(poll_url, headers, 0)
    end
  end

  defp do_poll(_poll_url, _headers, attempts) when attempts >= @max_poll_attempts do
    {:error, "Replicate prediction timed out after #{@max_poll_attempts} polls"}
  end

  defp do_poll(poll_url, headers, attempts) do
    Process.sleep(@poll_interval_ms)

    case Req.get(poll_url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        status = body["status"]

        case status do
          "succeeded" ->
            extract_output(body)

          "failed" ->
            {:error, Map.get(body, "error", "Prediction failed")}

          "canceled" ->
            {:error, "Prediction was canceled"}

          _ ->
            do_poll(poll_url, headers, attempts + 1)
        end

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "Replicate poll error (HTTP #{status}): #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, "Replicate poll failed: #{Exception.message(reason)}"}
    end
  end

  defp extract_output(body) do
    case body["output"] do
      [first | _] when is_binary(first) ->
        {:ok, first}

      output when is_binary(output) ->
        {:ok, output}

      output ->
        {:ok, Jason.encode!(output)}
    end
  end
end
