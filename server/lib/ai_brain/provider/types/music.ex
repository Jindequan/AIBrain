defmodule AIBrain.Provider.Types.Music do
  @moduledoc """
  Music generation via AI providers.
  Supports Replicate-hosted models (Stable Audio, MusicGen) and Suno API.
  """

  require Logger

  @default_model "meta/musicgen:671ac645ce5e552cc63a54a2bbff63fcf798043055d2dac5fc9e36a837eedcfb"
  @max_wait_ms 120_000
  @poll_interval_ms 2_000

  # ── Public API ────────────────────────────────────────────────────────

  @doc """
  Generate music from a text prompt.

  ## Options
    * `:provider_name` — provider name in registry (default: first active music provider)
    * `:model` — model to use
    * `:duration` — desired duration in seconds (model-dependent)
    * `:temperature` — creativity (0.0–1.0, default 0.8)

  Returns `{:ok, url_or_b64}` or `{:error, reason}`.
  """
  def generate(prompt, opts \\ []) do
    provider = resolve_provider(opts[:provider_name])

    case provider do
      nil ->
        {:error, "No music provider configured. Add one in Settings → Providers."}

      p ->
        if p.api_key && p.base_url do
          do_generate(provider_kind(p), p, prompt, opts)
        else
          {:error, "Provider '#{p.name}' not configured"}
        end
    end
  end

  # ── Suno API ──────────────────────────────────────────────────────────

  defp do_generate(:suno, %{base_url: base_url, api_key: api_key}, prompt, opts) do
    url = String.trim_trailing(base_url, "/") <> "/api/generate"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    body = %{
      "prompt" => prompt,
      "make_instrumental" => opts[:instrumental] || false,
      "wait_audio" => true
    }

    Logger.info("Suno generate: #{String.slice(prompt, 0, 60)}...")

    case Req.post(url, headers: headers, json: body, receive_timeout: @max_wait_ms) do
      {:ok, %{status: 200, body: %{"audio_url" => audio_url}}} ->
        {:ok, audio_url}

      {:ok, %{status: status, body: resp_body}} ->
        error_msg = extract_error(resp_body)
        {:error, "Suno API error (HTTP #{status}): #{error_msg}"}

      {:error, reason} ->
        {:error, "Suno API request failed: #{Exception.message(reason)}"}
    end
  end

  # ── Replicate API (Stable Audio / MusicGen) ───────────────────────────

  defp do_generate(:replicate, %{base_url: base_url, api_key: api_key}, prompt, opts) do
    model = opts[:model] || @default_model
    url = String.trim_trailing(base_url, "/") <> "/predictions"

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    body = %{
      "version" => model,
      "input" => %{
        "prompt" => prompt,
        "duration" => opts[:duration] || 30
      }
    }

    Logger.info(
      "MusicGen request: model=#{String.slice(model, 0, 30)}... prompt=#{String.slice(prompt, 0, 40)}"
    )

    case Req.post(url, headers: headers, json: body, receive_timeout: 30_000) do
      {:ok, %{status: 201, body: pred}} ->
        # Poll until complete
        poll_url = pred["urls"]["get"] || pred["urls"]["cancel"]
        do_music_poll(poll_url, headers, 0)

      {:ok, %{status: 200, body: pred}} ->
        poll_url = pred["urls"]["get"] || pred["urls"]["cancel"]
        do_music_poll(poll_url, headers, 0)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "Replicate music error (HTTP #{status}): #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, "Replicate music request failed: #{Exception.message(reason)}"}
    end
  end

  defp do_music_poll(_url, _headers, attempts) when attempts >= 30 do
    {:error, "Music generation timed out (60s)"}
  end

  defp do_music_poll(poll_url, headers, attempts) do
    Process.sleep(@poll_interval_ms)

    case Req.get(poll_url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        case body["status"] do
          "succeeded" ->
            output = body["output"]

            case output do
              url when is_binary(url) -> {:ok, url}
              [url | _] when is_binary(url) -> {:ok, url}
              _ -> {:ok, Jason.encode!(output)}
            end

          "failed" ->
            {:error, Map.get(body, "error", "Music generation failed")}

          "canceled" ->
            {:error, "Music generation was canceled"}

          _ ->
            do_music_poll(poll_url, headers, attempts + 1)
        end

      {:ok, %{status: status, body: resp_body}} ->
        {:error, "Music poll error (HTTP #{status}): #{inspect(resp_body)}"}

      {:error, reason} ->
        {:error, "Music poll failed: #{Exception.message(reason)}"}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp resolve_provider(nil) do
    case AIBrain.Provider.Registry.list() do
      [] ->
        nil

      providers ->
        Enum.find(providers, &(provider_kind(&1) == :suno)) ||
          Enum.find(providers, &(provider_kind(&1) == :replicate)) ||
          Enum.find(providers, &(&1.name =~ ~r/music/i))
    end
  end

  defp resolve_provider(name) do
    case AIBrain.Provider.Registry.get(name) do
      {:ok, p} -> p
      {:error, _} -> nil
    end
  end

  defp extract_error(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error(%{"error" => err}) when is_binary(err), do: err
  defp extract_error(_), do: "unknown error"

  defp provider_kind(%{name: name, base_url: base_url}) do
    marker = "#{name || ""} #{base_url || ""}"

    cond do
      marker =~ ~r/suno/i -> :suno
      marker =~ ~r/replicate/i -> :replicate
      true -> :replicate
    end
  end
end
