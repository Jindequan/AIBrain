defmodule AIBrain.Provider.ModelFetcher do
  @moduledoc """
  Fetches available models from provider APIs.

  Supports OpenAI-compatible providers (most of them) and special cases
  like Google Gemini (URL param auth) and Anthropic (no public API).

  Fetched models are cached to ~/.aibrain/cache/providers/{name}/models.json
  """

  require Logger
  alias AIBrain.Provider.Registry
  alias AIBrain.Config.FileBackend

  @doc """
  Fetch models from a provider and store them in the database.

  Supports an optional api_key override for temporary fetches without saving.

  Returns {:ok, %{created: n, updated: n, failed: n}} or {:error, reason}.
  """
  def fetch_models(provider_name, api_key_override \\ nil)

  def fetch_models(provider_name, nil) when is_binary(provider_name) do
    case Registry.get(provider_name) do
      {:ok, provider} ->
        do_fetch_models(provider)

      {:error, :not_found} ->
        {:error, "Provider not found: #{provider_name}"}
    end
  end

  def fetch_models(provider_name, api_key) when is_binary(provider_name) and is_binary(api_key) do
    case Registry.get(provider_name) do
      {:ok, provider} ->
        # 临时使用表单中的 API key，不保存到 Registry
        temp_provider = %{provider | api_key: api_key}
        do_fetch_models(temp_provider)

      {:error, :not_found} ->
        {:error, "Provider not found: #{provider_name}"}
    end
  end

  @doc """
  Fetch OpenRouter models AND provider metadata, merge into one cache/models.json.

  Fetches:
    1. https://openrouter.ai/api/v1/models — all models with context_length, modalities, pricing
    2. https://openrouter.ai/api/frontend/all-providers — provider icons, slugs, display names

  Saves as single enriched JSON: {"models": [...], "providers": [...], "fetched_at": "..."}

  Returns {:ok, %{models: count, providers: count}} or {:error, reason}.
  """
  def fetch_global_models do
    models_url = "https://openrouter.ai/api/v1/models"
    providers_url = "https://openrouter.ai/api/frontend/all-providers"

    models_result = fetch_models_from_openrouter(models_url)
    providers_result = fetch_providers_from_openrouter(providers_url)

    with {:ok, models} <- models_result,
         {:ok, providers} <- providers_result do
      # Build provider lookup by slug and name for model enrichment
      provider_by_slug = Map.new(providers, &{&1["slug"], &1})
      provider_by_name = Map.new(providers, &{String.downcase(&1["name"]), &1})

      # Enrich models with provider icon info
      enriched =
        Enum.map(models, fn m ->
          model_id = m["id"]
          # Extract provider slug from model id: "openai/gpt-4o" -> "openai"
          provider_slug = String.split(model_id, "/") |> List.first() || ""

          provider_meta =
            Map.get(provider_by_slug, provider_slug) ||
              Map.get(provider_by_name, String.downcase(provider_slug))

          m
          |> Map.put("provider_slug", provider_slug)
          |> Map.put("provider_icon", provider_meta["icon"])
          |> Map.put(
            "provider_display_name",
            provider_meta["display_name"] || provider_meta["name"]
          )
        end)

      FileBackend.save_global_models(enriched, providers)
      {:ok, %{models: length(models), providers: length(providers)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_models_from_openrouter(url) do
    case call_api(url, [], :get) do
      {:ok, %{"data" => models_list}} when is_list(models_list) ->
        models =
          Enum.map(models_list, fn m ->
            model_id = m["id"]
            architecture = m["architecture"] || %{}
            input_modalities = normalize_modalities(architecture["input_modalities"])
            output_modalities = normalize_modalities(architecture["output_modalities"])
            types = infer_types(input_modalities, output_modalities, architecture)

            %{
              "id" => model_id,
              "name" => m["name"] || model_id,
              "type" => List.first(types) || "text",
              "types" => types,
              "input_modalities" => input_modalities,
              "output_modalities" => output_modalities,
              "context_window" =>
                m["context_length"] || get_in(m, ["top_provider", "context_length"]),
              "max_completion_tokens" => get_in(m, ["top_provider", "max_completion_tokens"]),
              "description" => m["description"] || m["name"] || model_id,
              "supported_parameters" => m["supported_parameters"] || [],
              "pricing" => m["pricing"]
            }
          end)

        {:ok, models}

      {:ok, other} ->
        {:error, "Unexpected OpenRouter response: #{inspect(other)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_providers_from_openrouter(url) do
    case call_api(url, [], :get) do
      {:ok, %{"data" => providers_list}} when is_list(providers_list) ->
        providers =
          Enum.map(providers_list, fn p ->
            %{
              "id" => p["id"],
              "name" => p["name"],
              "display_name" => p["name"],
              "slug" => p["slug"],
              "icon" => get_in(p, ["icon", "url"])
            }
          end)

        {:ok, providers}

      {:ok, other} ->
        {:error, "Unexpected OpenRouter providers response: #{inspect(other)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Provider-specific fetchers ─────────────────────────────────────

  defp do_fetch_models(%{name: "google"} = provider) do
    # Google Gemini uses URL param for API key
    base_url = provider.fetch_models_url || provider.base_url
    api_key = provider.api_key

    if is_nil(api_key) or is_nil(base_url) do
      {:error, "Google provider requires api_key"}
    else
      url = base_url <> "?key=" <> URI.encode(api_key)

      case call_api(url, nil, :get) do
        {:ok, models_data} ->
          parse_google_models(models_data, provider)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_fetch_models(%{name: "anthropic"} = _provider) do
    # Anthropic has no public models API
    {:error, "Anthropic does not provide a public models API. Please add models manually."}
  end

  defp do_fetch_models(provider) do
    # Default: OpenAI-compatible format
    fetch_url = provider.fetch_models_url

    if is_nil(fetch_url) do
      {:error, "Provider #{provider.name} does not support model fetching"}
    else
      headers = build_headers(provider)
      has_key = headers != []

      Logger.debug(
        "[ModelFetcher] Fetching models for #{provider.name} from #{fetch_url} (auth: #{has_key})"
      )

      case call_api(fetch_url, headers, :get) do
        {:ok, models_data} ->
          parse_openai_models(models_data, provider)

        {:error, reason} ->
          Logger.warning("[ModelFetcher] Fetch failed for #{provider.name}: #{reason}")
          {:error, reason}
      end
    end
  end

  # ── API parsers ─────────────────────────────────────────────────────

  defp parse_openai_models(%{"data" => models_list}, provider) do
    models =
      Enum.map(models_list, fn model_data ->
        model_id = model_data["id"]
        model_type = infer_type_from_id(model_id)
        context_window = extract_context_window(model_data)

        %{
          "id" => generate_model_id(provider.name, model_id),
          "name" => model_id,
          "type" => model_type,
          "types" => [model_type],
          "input_modalities" => ["text"],
          "output_modalities" => [model_type],
          "context_window" => context_window,
          "description" => model_data["display_name"] || model_id,
          "supported_parameters" => model_data["supported_parameters"] || []
        }
      end)

    # Save to cache and merge into provider's models map
    FileBackend.save_cached_models(provider.name, models)
    merge_fetched_models(provider, models)

    {:ok, %{created: length(models), updated: 0, failed: 0}}
  end

  defp parse_google_models(%{"models" => models_list}, provider) do
    models =
      Enum.map(models_list, fn model_data ->
        model_id = model_data["name"]
        model_type = infer_type_from_id(model_id)
        context_window = extract_google_context_window(model_data)

        %{
          "id" => generate_model_id(provider.name, model_id),
          "name" => model_id,
          "type" => model_type,
          "types" => [model_type],
          "input_modalities" => ["text"],
          "output_modalities" => [model_type],
          "context_window" => context_window,
          "description" => model_data["description"] || model_id,
          "supported_parameters" => model_data["supportedGenerationMethods"] || []
        }
      end)

    # Save to cache and merge into provider's models map
    FileBackend.save_cached_models(provider.name, models)
    merge_fetched_models(provider, models)

    {:ok, %{created: length(models), updated: 0, failed: 0}}
  end

  # ── Merge fetched models into provider registry ─────────────────────

  defp merge_fetched_models(provider, models_list) do
    alias AIBrain.Provider.Registry

    # Build a models map from the fetched list, preserving any existing entries
    # for the same model names (manual settings like "enabled" persist across fetches).
    fetched =
      Enum.reduce(models_list, %{}, fn m, acc ->
        name = m["name"]
        existing = Map.get(provider.models, name, %{})

        Map.put(acc, name, %{
          "enabled" => Map.get(existing, "enabled", false),
          "context_window" => m["context_window"] || existing["context_window"],
          "max_output_tokens" => m["max_output_tokens"] || existing["max_output_tokens"],
          "type" => m["type"] || existing["type"] || "text",
          "types" => m["types"] || existing["types"] || ["text"],
          "input_modalities" => m["input_modalities"] || existing["input_modalities"] || ["text"],
          "output_modalities" => m["output_modalities"] || existing["output_modalities"] || ["text"],
          "description" => m["description"] || existing["description"] || name,
          "source" => "fetched"
        })
      end)

    updated = %{provider | models: Map.merge(provider.models, fetched)}
    Registry.update(provider.name, updated)
    Logger.info("[ModelFetcher] Merged #{map_size(fetched)} fetched models into #{provider.name}.models")
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp call_api(url, headers, method) when method in [:get, :post] do
    req = Req.new()

    request =
      if method == :get do
        Req.get(req, url: url, headers: headers)
      else
        Req.post(req, url: url, headers: headers)
      end

    case request do
      {:ok, %{status: 200, body: body}} ->
        data = decode_body(body)
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        message = extract_error_message(body, status)
        Logger.warning("[ModelFetcher] HTTP #{status} from #{url}: #{message}")
        {:error, message}

      {:error, reason} ->
        Logger.error("[ModelFetcher] Network error calling #{url}: #{inspect(reason)}")
        {:error, "网络错误：无法连接到 API 服务器"}
    end
  end

  defp decode_body(body) when is_map(body), do: body

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> %{}
    end
  end

  defp build_headers(%{api_key: nil}), do: []

  defp build_headers(%{api_key: key}) do
    [{"authorization", "Bearer #{key}"}]
  end

  defp extract_error_message(body, status) when is_map(body) do
    case body do
      %{"error" => %{"message" => msg}} when is_binary(msg) -> msg
      %{"error" => msg} when is_binary(msg) -> msg
      %{"message" => msg} when is_binary(msg) -> msg
      %{"detail" => msg} when is_binary(msg) -> msg
      _ -> "API 返回错误（HTTP #{status}）"
    end
  end

  defp extract_error_message(body, status) when is_binary(body) do
    # Some providers (e.g., SiliconFlow) return plain string errors
    if body != "" and String.length(body) < 200, do: body, else: "API 返回错误（HTTP #{status}）"
  end

  defp extract_error_message(_body, status), do: "API 返回错误（HTTP #{status}）"

  defp generate_model_id(provider_name, model_id) do
    # Generate a unique ID based on provider and model name
    "#{provider_name}__#{String.replace(model_id, "/", "__")}"
  end

  defp infer_type_from_id(model_id) do
    downcase = String.downcase(model_id)

    cond do
      String.contains?(downcase, ["image", "dall-e", "midjourney", "stable-diffusion"]) ->
        "image"

      String.contains?(downcase, ["video", "sora", "runway", "pika"]) ->
        "video"

      String.contains?(downcase, ["audio", "speech", "tts", "whisper"]) ->
        "audio"

      String.contains?(downcase, ["text-embedding", "embedding"]) ->
        "embedding"

      true ->
        "text"
    end
  end

  defp normalize_modalities(modalities) when is_list(modalities) do
    modalities
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(fn
      "text" -> "text"
      "image" -> "image"
      "video" -> "video"
      "audio" -> "audio"
      other -> other
    end)
    |> Enum.uniq()
  end

  defp normalize_modalities(_), do: []

  defp infer_types(input_modalities, output_modalities, architecture) do
    types =
      (input_modalities ++ output_modalities)
      |> Enum.filter(&(&1 in ["text", "image", "video", "audio"]))
      |> Enum.uniq()

    case types do
      [] -> [infer_type_from_modality(architecture)]
      _ -> types
    end
  end

  defp extract_context_window(model_data) do
    cond do
      model_data["context_window"] -> model_data["context_window"]
      model_data["context_length"] -> model_data["context_length"]
      model_data["max_tokens"] -> model_data["max_tokens"]
      model_data["max_context_length"] -> model_data["max_context_length"]
      model_data["max_input_tokens"] -> model_data["max_input_tokens"]
      true -> nil
    end
  end

  # Infer type from architecture.modality field (most accurate from OpenRouter)
  defp infer_type_from_modality(%{"modality" => modality}) when is_binary(modality) do
    downcase = String.downcase(modality)

    cond do
      # Image generation models
      String.contains?(downcase, ["image->", "image->image", "image+"]) ->
        "image"

      # Video generation models
      String.contains?(downcase, ["video->", "video->video"]) ->
        "video"

      # Audio/speech models
      String.contains?(downcase, ["audio->text", "audio->transcription"]) ->
        "audio"

      # Multimodal LLMs (text + image/file input)
      String.contains?(downcase, ["text+image", "text+file"]) ->
        "text"

      # Text-only LLMs
      String.contains?(downcase, ["text->text"]) ->
        "text"

      true ->
        "text"
    end
  end

  defp extract_google_context_window(model_data) do
    cond do
      model_data["contextWindow"] -> model_data["contextWindow"]
      model_data["context_window"] -> model_data["context_window"]
      model_data["max_tokens"] -> model_data["max_tokens"]
      true -> nil
    end
  end
end
