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
  Model list for ChatInput ModelSelector.
  Returns user's enabled models from providers that have API keys.
  """
  def handle_list_all_models(conn) do
    config = AIBrain.Config.ProviderConfig.load_config()
    providers_cfg = Map.get(config, "providers", %{})

    models =
      providers_cfg
      |> Enum.filter(fn {name, _cfg} ->
        AIBrain.LLM.Provider.has_api_key?(String.to_atom(name))
      end)
      |> Enum.flat_map(fn {provider, _cfg} ->
        enabled = AIBrain.Config.ProviderConfig.enabled_models(provider)
        provider_atom = String.to_atom(provider)

        case enabled do
          :all ->
            try do
              AIBrain.Provider.Catalog.models_for_provider(provider_atom)
            rescue
              _ -> []
            end

          model_ids when is_list(model_ids) ->
            model_ids
            |> Enum.map(fn model_id ->
              try do
                case LLMDB.model(provider_atom, model_id) do
                  {:ok, m} ->
                    %{
                      "id" => m.id,
                      "name" => m.name || m.id,
                      "provider" => provider,
                      "context_length" => get_in(m, [Access.key(:limits), Access.key(:context)]),
                      "max_output_tokens" => max_output_from_model(m)
                    }
                  _ ->
                    %{"id" => model_id, "name" => model_id, "provider" => provider,
                      "context_length" => nil, "max_output_tokens" => nil}
                end
              rescue
                _ ->
                  %{"id" => model_id, "name" => model_id, "provider" => provider,
                    "context_length" => nil, "max_output_tokens" => nil}
              end
            end)
        end
      end)
      |> Enum.map(fn m ->
        %{
          id: m["id"],
          name: m["name"],
          provider: m["provider"],
          context_window: m["context_length"],
          max_output_tokens: m["max_output_tokens"],
          enabled: true
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

  # ── Catalog (read-only LLMDB) ────────────────────────────

  @doc """
  GET /api/v1/catalog/providers — all providers from LLMDB.
  """
  def handle_catalog_providers(conn) do
    entries = AIBrain.Provider.Catalog.provider_entries()

    providers =
      Enum.map(entries, fn entry ->
        %{
          id: entry.name,
          name: entry.display_name,
          base_url: entry.base_url,
          env_key: entry.env_key
        }
      end)

    json_response(conn, 200, %{providers: providers})
  end

  @doc """
  GET /api/v1/catalog/providers/:id/models — all models for a provider from LLMDB.
  Read-only reference data for browsing/discovery.
  """
  def handle_catalog_provider_models(conn, id) do
    provider_atom = String.to_atom(id)

    models =
      try do
        AIBrain.Provider.Catalog.models_for_provider(provider_atom)
        |> Enum.map(fn m ->
          %{
            id: m["id"],
            name: m["name"],
            full_id: m["full_id"],
            provider: m["provider"],
            context_length: m["context_length"],
            max_output_tokens: m["max_output_tokens"],
            input_modalities: m["input_modalities"] || ["text"],
            output_modalities: m["output_modalities"] || ["text"],
            description: m["description"] || ""
          }
        end)
      rescue
        _ -> []
      end

    json_response(conn, 200, %{ok: true, provider: id, models: models})
  end

  # ── My Models (user config) ──────────────────────────────

  @doc """
  GET /api/v1/my-models — user's active providers + enabled models + default.
  This is the small curated set the backend uses for routing.
  """
  def handle_my_models(conn) do
    config = AIBrain.Config.ProviderConfig.load_config()
    providers_cfg = Map.get(config, "providers", %{})
    catalog_entries = AIBrain.Provider.Catalog.provider_entries()

    default_model =
      case AIBrain.Data.SystemSetting.default_llm_model() do
        {p, m} when is_binary(p) and is_binary(m) -> "#{p}:#{m}"
        _ -> nil
      end

    providers =
      build_my_providers(providers_cfg, catalog_entries)
      |> Enum.sort_by(&{not (&1.enabled and &1.has_key), &1.name})

    models = build_my_models(providers_cfg, catalog_entries, default_model)

    setup_required =
      not Enum.any?(providers, fn p -> p.enabled and p.has_key end) or is_nil(default_model)

    json_response(conn, 200, %{
      providers: providers,
      models: models,
      default_model: default_model,
      setup_required: setup_required
    })
  end

  defp build_my_providers(providers_cfg, catalog_entries) do
    catalog_names = Enum.map(catalog_entries, & &1.name) |> MapSet.new()

    catalog_providers =
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
          priority: Map.get(p_cfg, "priority", 0)
        }
      end)

    custom_providers =
      providers_cfg
      |> Enum.reject(fn {n, _} -> MapSet.member?(catalog_names, n) end)
      |> Enum.map(fn {n, cfg} ->
        atom = String.to_atom(n)
        has_key = AIBrain.LLM.Provider.has_api_key?(atom)

        %{
          id: n,
          name: n,
          enabled: Map.get(cfg, "enabled", true) and has_key,
          base_url: Map.get(cfg, "base_url"),
          env_key: nil,
          has_key: has_key,
          custom: true,
          priority: Map.get(cfg, "priority", 0)
        }
      end)

    catalog_providers ++ custom_providers
  end

  defp build_my_models(providers_cfg, _catalog_entries, default_model) do
    providers_cfg
    |> Enum.flat_map(fn {provider, _cfg} ->
      enabled = AIBrain.Config.ProviderConfig.enabled_models(provider)
      provider_atom = String.to_atom(provider)

      models =
        case enabled do
          :all ->
            try do
              AIBrain.Provider.Catalog.models_for_provider(provider_atom)
            rescue
              _ -> []
            end

          model_ids when is_list(model_ids) ->
            model_ids
            |> Enum.map(fn model_id ->
              try do
                case LLMDB.model(provider_atom, model_id) do
                  {:ok, m} ->
                    %{
                      "id" => m.id,
                      "name" => m.name || m.id,
                      "full_id" => "#{provider}:#{m.id}",
                      "provider" => provider,
                      "context_length" => get_in(m, [Access.key(:limits), Access.key(:context)]),
                      "max_output_tokens" => max_output_from_model(m),
                      "input_modalities" => modality_list(m, :input),
                      "output_modalities" => modality_list(m, :output),
                      "description" => m.name || m.id
                    }

                  _ ->
                    %{
                      "id" => model_id,
                      "name" => model_id,
                      "full_id" => "#{provider}:#{model_id}",
                      "provider" => provider,
                      "context_length" => nil,
                      "max_output_tokens" => nil,
                      "input_modalities" => ["text"],
                      "output_modalities" => ["text"],
                      "description" => model_id
                    }
                end
              rescue
                _ ->
                  %{
                    "id" => model_id,
                    "name" => model_id,
                    "full_id" => "#{provider}:#{model_id}",
                    "provider" => provider,
                    "context_length" => nil,
                    "max_output_tokens" => nil,
                    "input_modalities" => ["text"],
                    "output_modalities" => ["text"],
                    "description" => model_id
                  }
              end
            end)
        end

      Enum.map(models, fn m ->
        full_id = m["full_id"] || "#{provider}:#{m["id"]}"

        %{
          id: m["id"],
          name: m["name"],
          full_id: full_id,
          provider: provider,
          context_length: m["context_length"],
          max_output_tokens: m["max_output_tokens"],
          input_modalities: m["input_modalities"] || ["text"],
          output_modalities: m["output_modalities"] || ["text"],
          description: m["description"] || "",
          enabled: true,
          default: full_id == default_model
        }
      end)
    end)
  end

  defp max_output_from_model(model) do
    get_in(model, [Access.key(:limits), Access.key(:output)])
  end

  defp modality_list(model, direction) do
    case get_in(model, [Access.key(:modalities), direction]) do
      nil -> ["text"]
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> ["text"]
    end
  end

  @doc """
  PUT /api/v1/my-models/models/:provider/:model — enable a model.
  """
  def handle_my_models_enable_model(conn, provider, model) do
    AIBrain.Config.ProviderConfig.enable_model(provider, model)
    json_response(conn, 200, %{ok: true, provider: provider, model: model, enabled: true})
  end

  @doc """
  DELETE /api/v1/my-models/models/:provider/:model — disable a model.
  """
  def handle_my_models_disable_model(conn, provider, model) do
    AIBrain.Config.ProviderConfig.disable_model(provider, model)

    # If this was the default model, clear it
    case AIBrain.Data.SystemSetting.default_llm_model() do
      {^provider, ^model} ->
        AIBrain.Data.SystemSetting.set_default_llm_model({nil, nil})

      _ ->
        :ok
    end

    json_response(conn, 200, %{ok: true, provider: provider, model: model, enabled: false})
  end

  @doc """
  PUT /api/v1/my-models/default — set default model.
  Body: { provider, model }
  """
  def handle_my_models_set_default(conn, params) do
    provider = params["provider"]
    model = params["model"]

    if is_binary(provider) and is_binary(model) do
      AIBrain.Data.SystemSetting.set_default_llm_model({provider, model})
      json_response(conn, 200, %{ok: true, provider: provider, model: model})
    else
      json_response(conn, 400, %{error: "provider and model are required"})
    end
  end

  @doc """
  PATCH /api/v1/my-models/providers/:id — configure a provider.
  Body: { enabled, base_url?, priority? }
  """
  def handle_my_models_configure_provider(conn, id, params) do
    enabled = params["enabled"]

    if enabled == true do
      AIBrain.Config.ProviderConfig.enable_provider(id)
    else
      AIBrain.Config.ProviderConfig.disable_provider(id)
    end

    if base_url = params["base_url"] do
      AIBrain.Config.ProviderConfig.set_base_url(id, base_url)
    end

    if priority = params["priority"] do
      AIBrain.Config.ProviderConfig.set_provider_priority(id, priority)
    end

    json_response(conn, 200, %{ok: true, id: id})
  end

  @doc """
  POST /api/v1/my-models/credentials — store an API key.
  Body: { provider, api_key }
  """
  def handle_my_models_store_credential(conn, params) do
    provider = params["provider"]
    api_key = params["api_key"]

    if is_nil(provider) or provider == "" do
      json_response(conn, 400, %{error: "Provider name required"})
    else
      atom = String.to_atom(provider)
      AIBrain.LLM.Provider.put_api_key(atom, api_key)
      AIBrain.Config.ProviderConfig.enable_provider(provider)
      json_response(conn, 200, %{ok: true, provider: provider})
    end
  end

  @doc """
  DELETE /api/v1/my-models/providers/:id — delete a provider config.
  """
  def handle_my_models_delete_provider(conn, id) do
    atom = String.to_atom(id)
    AIBrain.LLM.Provider.put_api_key(atom, "")
    AIBrain.Config.ProviderConfig.disable_provider(id)
    json_response(conn, 200, %{ok: true, id: id})
  end

  # ── Catalog refresh ──────────────────────────────────────

  @doc """
  POST /api/v1/catalog/refresh — reload LLMDB snapshot.
  """
  def handle_catalog_refresh(conn) do
    try do
      LLMDB.load()
    rescue
      _ -> :ok
    end

    AIBrain.Config.ProviderConfig.cache_invalidate()
    json_response(conn, 200, %{ok: true})
  end

  @doc """
  GET /api/v1/providers/:id/models — list models for ONE provider from catalog.
  """
  def handle_list_models(conn, id) do
    provider_atom = String.to_atom(id)

    default_model =
      case AIBrain.Data.SystemSetting.default_llm_model() do
        {_p, m} -> m
        _ -> nil
      end

    models =
      try do
        AIBrain.Provider.Catalog.models_for_provider(provider_atom)
        |> Enum.map(fn m ->
          model_name = m["id"]
          %{
            id: model_name,
            name: m["name"],
            full_id: m["full_id"],
            provider: m["provider"],
            context_length: m["context_length"],
            max_output_tokens: m["max_output_tokens"],
            input_modalities: m["input_modalities"] || ["text"],
            output_modalities: m["output_modalities"] || ["text"],
            description: m["description"] || "",
            enabled: AIBrain.Config.ProviderConfig.model_enabled?(id, model_name),
            default: model_name == default_model
          }
        end)
      rescue
        _ -> []
      end

    json_response(conn, 200, %{ok: true, provider: id, models: models})
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
