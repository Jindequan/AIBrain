defmodule AIBrain.Web.Handlers.ProvidersHandler do
  import Plug.Conn
  require Logger

  alias AIBrain.Config.ProviderConfig
  alias AIBrain.LLM.Provider, as: LLMProvider

  @doc """
  List all known providers from ReqLLM with their key/config status.
  """
  def handle_list(conn) do
    # Start with known ReqLLM providers
    known = LLMProvider.list_providers()

    # Also include any providers configured locally (custom providers)
    local_config = ProviderConfig.load_config()
    local_names =
      local_config
      |> Map.get("providers", %{})
      |> Map.keys()
      |> Enum.map(&String.to_atom/1)

    all_providers = (known ++ local_names) |> Enum.uniq()

    providers =
      all_providers
      |> Enum.map(&build_provider_summary/1)
      |> Enum.sort_by(& {not (&1.configured and &1.enabled), &1.name})

    json_response(conn, 200, %{providers: providers})
  end

  @doc """
  Store an API key for a provider and enable it.
  Body: { "name": "openai", "api_key": "sk-..." }
  """
  def handle_add(conn, params) do
    name = normalize_string(params["name"])
    api_key = normalize_secret(params["api_key"])

    cond do
      is_nil(name) or name == "" ->
        json_response(conn, 400, %{error: "Provider name is required"})

      is_nil(api_key) or api_key == "" ->
        json_response(conn, 400, %{error: "API key is required"})

      true ->
        provider_atom = to_provider_atom(name)
        LLMProvider.put_api_key(provider_atom, api_key)
        ProviderConfig.enable_provider(name)
        json_response(conn, 201, %{ok: true, name: name})
    end
  end

  @doc """
  Update a provider's key or config.
  """
  def handle_update(conn, id, params) do
    name = normalize_string(params["name"]) || id

    # Handle rename: copy key and config from old name to new name
    if name != id do
      old_atom = to_provider_atom(id)
      new_atom = to_provider_atom(name)

      # Transfer API key
      case ReqLLM.get_key(:"#{old_atom}_api_key") do
        key when is_binary(key) and key != "" ->
          LLMProvider.put_api_key(new_atom, key)
          LLMProvider.put_api_key(old_atom, "")
        _ -> :ok
      end

      # Transfer local config
      old_cfg = ProviderConfig.get_provider_config(id)
      if old_cfg["enabled"] do
        ProviderConfig.enable_provider(name)
        ProviderConfig.disable_provider(id)
      end
      if priority = old_cfg["priority"], do: ProviderConfig.set_provider_priority(name, priority)
      if base_url = old_cfg["base_url"], do: ProviderConfig.set_base_url(name, base_url)
    else
      provider_atom = to_provider_atom(name)

      # Update API key if provided
      if api_key = normalize_secret(params["api_key"]) do
        LLMProvider.put_api_key(provider_atom, api_key)
      end

      # Clear key if explicitly set to empty
      if Map.has_key?(params, "api_key") && blank?(params["api_key"]) do
        LLMProvider.put_api_key(provider_atom, "")
      end

      # Update enabled status
      enabled = params["enabled"]
      if enabled == true, do: ProviderConfig.enable_provider(name)
      if enabled == false, do: ProviderConfig.disable_provider(name)

      # Update priority
      if priority = params["priority"] do
        ProviderConfig.set_provider_priority(name, priority)
      end

      # Update base_url
      if base_url = normalize_string(params["base_url"]) do
        ProviderConfig.set_base_url(name, base_url)
      end
    end

    json_response(conn, 200, %{ok: true, name: name})
  end

  @doc """
  Delete/disable a provider.
  """
  def handle_delete(conn, id) do
    LLMProvider.put_api_key(to_provider_atom(id), "")
    ProviderConfig.disable_provider(id)
    json_response(conn, 200, %{ok: true, name: id})
  end

  def handle_enable(conn, id) do
    ProviderConfig.enable_provider(id)
    json_response(conn, 200, %{ok: true, name: id, enabled: true})
  end

  def handle_disable(conn, id) do
    ProviderConfig.disable_provider(id)
    json_response(conn, 200, %{ok: true, name: id, enabled: false})
  end

  @doc """
  Fetch models for a provider from LLMDB.
  This replaces the old ModelFetcher which called provider-specific APIs.
  """
  def handle_fetch_models(conn, id) do
    provider_atom = to_provider_atom(id)

    try do
      models = LLMDB.models(provider_atom)

      if models != [] do
        json_response(conn, 200, %{
          ok: true,
          provider: id,
          models: Enum.map(models, &serialize_llmdb_model/1),
          count: length(models)
        })
      else
        json_response(conn, 200, %{
          ok: true,
          provider: id,
          models: [],
          count: 0,
          note: "No models found in LLMDB for #{id}. Models are pre-shipped with the llm_db package."
        })
      end
    rescue
      e ->
        Logger.error("Failed to fetch models for #{id}: #{Exception.message(e)}")
        json_response(conn, 500, %{error: "Failed to fetch models: #{Exception.message(e)}"})
    end
  end

  @doc """
  Fetch all models count — lightweight, does not load model data.
  Per-provider model loading is done via GET /api/v1/providers/:id/models.
  """
  def handle_fetch_all_models(conn) do
    count = LLMProvider.list_providers() |> length()
    json_response(conn, 200, %{ok: true, count: count, providers: count,
      note: "Per-provider models: GET /api/v1/providers/:id/models"})
  end

  @doc """
  List models for a specific provider from LLMDB (query param).
  """
  def handle_list_provider_models(conn, params) do
    provider = params["provider"]
    if is_nil(provider) or provider == "" do
      json_response(conn, 400, %{error: "provider query parameter is required"})
    else
      handle_list_models(conn, provider)
    end
  end

  @doc """
  Lightweight model summary for ChatInput ModelSelector.
  Returns ONLY per-provider model counts, not full model data.
  Full model data is loaded on demand via GET /api/v1/providers/:id/models.
  """
  def handle_list_all_models(conn) do
    providers_with_keys =
      LLMProvider.list_providers()
      |> Enum.filter(&LLMProvider.has_api_key?/1)

    # Return minimal info: provider names only. Models loaded lazily per provider.
    models =
      Enum.map(providers_with_keys, fn provider_atom ->
        pname = Atom.to_string(provider_atom)
        %{
          provider: pname,
          name: pname,
          type: "text",
          input_modalities: ["text"],
          output_modalities: ["text"],
          description: "Models from #{pname}",
          enabled: true,
          context_window: nil,
          max_output_tokens: nil,
          icon_url: nil
        }
      end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{models: models}))
  end

  @doc """
  Check if a model is allowed as a default for a category.
  """
  def default_model_allowed?(category, provider, model_name) do
    try do
      atom = to_provider_atom(provider)

      case LLMDB.model(atom, model_name) do
        {:ok, model} ->
          default_category_match?(category, model)

        _ ->
          true
      end
    rescue
      _ -> true
    end
  end

  # -- OpenRouter helpers (simplified -- no more separate fetch) --

  def handle_list_openrouter_providers(conn) do
    # Return empty list; OpenRouter providers are part of LLMDB now
    json_response(conn, 200, %{providers: []})
  end

  def handle_fetch_openrouter_providers(conn) do
    # LLMDB handles model data; no separate fetch needed
    json_response(conn, 200, %{ok: true, models: 0, providers: 0,
      note: "Models are managed by LLMDB. Use /models/all to list all models."})
  end

  # -- Config management --

  def handle_get_config(conn, _params) do
    known = LLMProvider.list_providers()

    local_config = ProviderConfig.load_config()
    local_names =
      local_config
      |> Map.get("providers", %{})
      |> Map.keys()
      |> Enum.map(&String.to_atom/1)

    all_providers = (known ++ local_names) |> Enum.uniq()

    providers =
      all_providers
      |> Enum.map(fn atom ->
        name = Atom.to_string(atom)
        %{
          name: name,
          configured: LLMProvider.has_api_key?(atom),
          has_api_key: LLMProvider.has_api_key?(atom),
          api_key: nil,
          base_url: ProviderConfig.get_base_url(name),
          priority: ProviderConfig.get_provider_priority(name),
          enabled: ProviderConfig.provider_enabled?(name),
          models: %{},
          enabled_models: ProviderConfig.enabled_models(name)
        }
      end)

    json_response(conn, 200, %{providers: providers})
  end

  def handle_save_config(conn, body) do
    providers_list =
      cond do
        is_map(body) and Map.has_key?(body, "providers") -> body["providers"]
        is_list(body) -> body
        true -> []
      end

    Enum.each(providers_list, fn p ->
      name = p["name"]
      if name && name != "" do
        if p["api_key"] && p["api_key"] != "" do
          LLMProvider.put_api_key(to_provider_atom(name), p["api_key"])
        end

        enabled = p["enabled"]
        if enabled == true, do: ProviderConfig.enable_provider(name)
        if enabled == false, do: ProviderConfig.disable_provider(name)

        if priority = p["priority"] do
          ProviderConfig.set_provider_priority(name, priority)
        end

        if base_url = p["base_url"] do
          ProviderConfig.set_base_url(name, base_url)
        end
      end
    end)

    json_response(conn, 200, %{ok: true})
  end

  # -- Model Settings (unified view model, like Jinn) --

  @doc """
  GET /api/v1/model-settings — providers overview + enabled model IDs only.
  Models are NOT included. Use GET /api/v1/providers/:id/models for per-provider model list.
  """
  def handle_model_settings(conn) do
    json_response(conn, 200, build_model_settings())
  end

  defp build_model_settings do
    case :persistent_term.get(:ai_brain_model_settings, nil) do
      nil ->
        data = compute_and_cache()
        :persistent_term.put(:ai_brain_model_settings, data)
        data
      cached ->
        cached
    end
  end

  defp compute_and_cache do
    catalog_entries = AIBrain.Provider.Catalog.provider_entries()
    config = AIBrain.Config.ProviderConfig.load_config()
    providers_cfg = Map.get(config, "providers", %{})

    enabled_model_ids = get_enabled_model_ids(providers_cfg)

    default_model =
      case AIBrain.Data.SystemSetting.default_llm_model() do
        {p, m} when is_binary(p) and is_binary(m) -> "#{p}:#{m}"
        _ -> List.first(enabled_model_ids)
      end

    providers =
      Enum.map(catalog_entries, fn entry ->
        name = entry.name
        has_key = AIBrain.LLM.Provider.has_api_key?(entry.id)
        p_cfg = Map.get(providers_cfg, name, %{})

        %{
          id: name,
          name: entry.display_name,
          enabled: Map.get(p_cfg, "enabled", true) and has_key,
          base_url: entry.base_url || Map.get(p_cfg, "base_url"),
          env_key: entry.env_key,
          has_key: has_key,
          custom: false,
          provider_type: name,
          updated_at: nil
        }
      end)
      |> then(fn catalog_providers ->
        custom =
          providers_cfg
          |> Enum.reject(fn {n, _} -> Enum.any?(catalog_entries, fn e -> e.name == n end) end)
          |> Enum.map(fn {n, cfg} ->
            atom = String.to_atom(n)
            %{id: n, name: n, enabled: Map.get(cfg, "enabled", true) and AIBrain.LLM.Provider.has_api_key?(atom),
              base_url: Map.get(cfg, "base_url"), env_key: nil, has_key: AIBrain.LLM.Provider.has_api_key?(atom),
              custom: true, provider_type: "openai", updated_at: nil}
          end)
        catalog_providers ++ custom
      end)
      |> Enum.sort_by(& {not (&1.enabled and &1.has_key), &1.name})

    setup_required =
      not Enum.any?(providers, fn p -> p.enabled and p.has_key end) or is_nil(default_model)

    data = %{
      providers: providers,
      enabled_models: enabled_model_ids,
      disabled_models: get_all_disabled_models(providers_cfg),
      default_model: default_model,
      setup_required: setup_required,
      catalog: %{
        source: "llmdb",
        provider_count: length(catalog_entries),
        model_count: estimate_model_count(),
        refreshed_at: nil
      }
    }

    :persistent_term.put(:ai_brain_model_settings, data)
    data
  end

  # Only query LLMDB when we absolutely need model details (per-provider view).
  # enabled_model_ids are computed lazily from config, without touching LLMDB.
  defp get_enabled_model_ids(_providers_cfg) do
    # All models default to enabled. Only disabled ones have entries in config.
    # We can't enumerate 1330 models here. Instead return nil as sentinel
    # meaning "all models enabled unless explicitly disabled in config".
    :all
  end

  defp get_all_disabled_models(providers_cfg) do
    Enum.flat_map(providers_cfg, fn {provider, cfg} ->
      (Map.get(cfg, "disabled_models", []) || [])
      |> Enum.map(fn model -> "#{provider}:#{model}" end)
    end)
  end

  defp estimate_model_count, do: 1330

  @doc """
  GET /api/v1/providers/:id/models — list models for ONE provider.
  This is the only endpoint that queries LLMDB. Called per-provider, lazily.
  """
  def handle_list_models(conn, id) do
    provider_atom = String.to_atom(id)
    config = AIBrain.Config.ProviderConfig.load_config()
    providers_cfg = Map.get(config, "providers", %{})
    p_cfg = Map.get(providers_cfg, id, %{})
    disabled_models = Map.get(p_cfg, "disabled_models", [])

    default_model =
      case AIBrain.Data.SystemSetting.default_llm_model() do
        {_p, m} -> m
        _ -> nil
      end

    models =
      try do
        AIBrain.Provider.Catalog.models_for_provider(provider_atom)
        |> Enum.map(fn m ->
          model_name = m["name"]
          %{
            id: m["id"],
            name: model_name,
            provider: m["provider"],
            context_length: m["context_length"],
            max_output_tokens: m["max_output_tokens"],
            input_modalities: m["input_modalities"] || ["text"],
            output_modalities: m["output_modalities"] || ["text"],
            description: m["description"] || "",
            enabled: model_name not in disabled_models,
            default: model_name == default_model
          }
        end)
      rescue
        _ -> []
      end

    json_response(conn, 200, %{ok: true, provider: id, models: models})
  end

  @doc """
  POST /api/v1/settings/providers — configure a provider.
  Body: { name, enabled, base_url?, custom?, provider_type? }
  """
  def handle_configure_provider(conn, params) do
    name = params["name"]
    enabled = params["enabled"]
    base_url = params["base_url"]

    if is_nil(name) or name == "" do
      json_response(conn, 400, %{error: "Provider name required"})
    else
      if enabled == true do
        AIBrain.Config.ProviderConfig.enable_provider(name)
      else
        AIBrain.Config.ProviderConfig.disable_provider(name)
      end

      if base_url do
        AIBrain.Config.ProviderConfig.set_base_url(name, base_url)
      end

      # Invalidate cache and return updated settings
      model_settings_cache_invalidate()
      json_response(conn, 200, compute_and_cache())
    end
  end

  @doc """
  POST /api/v1/settings/credentials — store an API key.
  Body: { provider, api_key }
  """
  def handle_store_credential(conn, params) do
    provider = params["provider"]
    api_key = params["api_key"]

    if is_nil(provider) or provider == "" do
      json_response(conn, 400, %{error: "Provider name required"})
    else
      atom = String.to_atom(provider)
      AIBrain.LLM.Provider.put_api_key(atom, api_key)
      AIBrain.Config.ProviderConfig.enable_provider(provider)

      model_settings_cache_invalidate()
      json_response(conn, 200, compute_and_cache())
    end
  end

  @doc """
  DELETE /api/v1/settings/providers/:name — delete a provider.
  """
  def handle_delete_provider_settings(conn, name) do
    atom = String.to_atom(name)
    AIBrain.LLM.Provider.put_api_key(atom, "")
    AIBrain.Config.ProviderConfig.disable_provider(name)

    model_settings_cache_invalidate()
    json_response(conn, 200, compute_and_cache())
  end

  @doc """
  POST /api/v1/settings/model-policy — update enabled_models + default_model.
  Body: { toggle_model: "provider:model", enabled: bool }  ← O(1) single toggle
        { enabled_models: [...], default_model: "provider:model" }  ← legacy full sync
  """
  def handle_update_model_policy(conn, params) do
    default_model = params["default_model"]
    toggle_model = params["toggle_model"]

    # Single-model toggle path: O(1) — no iteration over catalog
    if is_binary(toggle_model) and toggle_model != "" do
      enabled = params["enabled"] != false
      AIBrain.Config.ProviderConfig.toggle_model(toggle_model, enabled)
    end

    # Update default model
    if default_model do
      case String.split(default_model, ":", parts: 2) do
        [p, m] -> AIBrain.Data.SystemSetting.set_default_llm_model({p, m})
        _ -> :ok
      end
    end

    model_settings_cache_invalidate()
    json_response(conn, 200, compute_and_cache())
  end

  defp model_settings_cache_invalidate do
    :persistent_term.erase(:ai_brain_model_settings)
  rescue
    _ -> :ok
  end

  @doc """
  POST /api/v1/settings/catalog/refresh — reload LLMDB snapshot and refresh catalog.
  """
  def handle_refresh_catalog(conn) do
    # Reload the model database to pick up any new models
    try do
      LLMDB.load()
    rescue
      _ -> :ok
    end

    model_settings_cache_invalidate()
    AIBrain.Config.ProviderConfig.cache_invalidate()
    json_response(conn, 200, compute_and_cache())
  end

  # -- Private helpers --

  defp build_provider_summary(provider_atom) do
    name = Atom.to_string(provider_atom)
    cfg = ProviderConfig.get_provider_config(name)

    %{
      name: name,
      display_name: provider_display_name(provider_atom),
      configured: LLMProvider.has_api_key?(provider_atom),
      has_api_key: LLMProvider.has_api_key?(provider_atom),
      api_key: nil,
      base_url: Map.get(cfg, "base_url") || infer_base_url(provider_atom),
      fetch_models_url: nil,
      chat_url: nil,
      priority: Map.get(cfg, "priority", 0),
      enabled: Map.get(cfg, "enabled", true),
      models: %{},
      enabled_models: ProviderConfig.enabled_models(name),
      supports_model_fetch: true
    }
  end

  defp provider_display_name(atom) do
    case atom do
      :openai -> "OpenAI"
      :anthropic -> "Anthropic"
      :google -> "Google Gemini"
      :google_vertex -> "Google Vertex AI"
      :azure -> "Azure"
      :aws_bedrock -> "AWS Bedrock"
      :groq -> "Groq"
      :xai -> "xAI"
      :openrouter -> "OpenRouter"
      :cerebras -> "Cerebras"
      :fireworks_ai -> "Fireworks AI"
      :meta -> "Meta"
      :mistral -> "Mistral"
      :together -> "Together"
      :ollama -> "Ollama"
      :vllm -> "vLLM"
      :nearai -> "NearAI"
      :zai -> "Z.AI"
      :zai_coder -> "Z.AI Coder"
      :zenmux -> "ZenMux"
      :alibaba -> "Alibaba"
      :alibaba_cn -> "Alibaba CN"
      :minimax -> "MiniMax"
      :deepseek -> "DeepSeek"
      :baichuan -> "Baichuan"
      :qianfan -> "Qianfan"
      _ -> Atom.to_string(atom) |> String.split("-") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
    end
  end

  defp infer_base_url(atom) do
    case atom do
      :openai -> "https://api.openai.com/v1"
      :anthropic -> "https://api.anthropic.com"
      :google -> "https://generativelanguage.googleapis.com/v1beta"
      :groq -> "https://api.groq.com/openai/v1"
      :openrouter -> "https://openrouter.ai/api/v1"
      :mistral -> "https://api.mistral.ai/v1"
      :deepseek -> "https://api.deepseek.com/v1"
      :xai -> "https://api.x.ai/v1"
      :cerebras -> "https://api.cerebras.ai/v1"
      :fireworks_ai -> "https://api.fireworks.ai/inference/v1"
      _ -> nil
    end
  end

  defp serialize_llmdb_model(model) do
    %{
      "id" => model.id,
      "name" => model.id,
      "provider" => Atom.to_string(model.provider),
      "context_window" => model.context_window,
      "max_output_tokens" => model.max_output_tokens,
      "input_modalities" => model.input_modalities || ["text"],
      "output_modalities" => model.output_modalities || ["text"],
      "type" => model_modality(model, "text"),
      "types" => model_modalities(model),
      "description" => model.description || "",
      "enabled" => true,
      "source" => "llmdb"
    }
  end

  defp model_modalities(model) do
    (model.input_modalities || []) ++ (model.output_modalities || [])
    |> Enum.uniq()
    |> Enum.filter(&(&1 in ["text", "image", "video", "audio"]))
    |> case do
      [] -> ["text"]
      mods -> mods
    end
  end

  defp model_modality(model, default) do
    mods = model_modalities(model)
    if length(mods) == 1, do: hd(mods), else: default
  end

  defp default_category_match?(_category, _model), do: false

  defp to_provider_atom(name) when is_binary(name) do
    String.to_atom(name)
  rescue
    _ -> String.to_atom(String.downcase(name))
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(_), do: nil

  defp normalize_secret(value), do: normalize_string(value)

  defp blank?(nil), do: true
  defp blank?(str) when is_binary(str), do: String.trim(str) == ""
  defp blank?(_), do: true

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
