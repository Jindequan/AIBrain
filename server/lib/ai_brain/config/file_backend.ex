defmodule AIBrain.Config.FileBackend do
  @moduledoc """
  Manages provider configuration stored in ~/.aibrain/providers.json.
  """

  require Logger
  import Jason

  @aibrain_dir ".aibrain"
  @providers_file "providers.json"
  @cache_dir "cache/providers"

  @doc "Get the aibrain directory path"
  def aibrain_dir do
    Application.get_env(:ai_brain, :config_dir) || Path.join(System.user_home(), @aibrain_dir)
  end

  @doc "Get the providers config file path"
  def providers_file do
    Path.join(aibrain_dir(), @providers_file)
  end

  @doc "Get the cache directory for a specific provider"
  def provider_cache_dir(provider_name) do
    Path.join([aibrain_dir(), @cache_dir, provider_name])
  end

  @doc "Get the cached models file path for a provider"
  def cached_models_file(provider_name) do
    Path.join(provider_cache_dir(provider_name), "models.json")
  end

  @doc "Ensure aibrain directory exists"
  def ensure_aibrain_dir do
    dir = aibrain_dir()
    File.mkdir_p!(dir)
    dir
  end

  @doc "Load providers from config file"
  def load_providers do
    file = providers_file()

    if File.exists?(file) do
      case File.read(file) do
        {:ok, content} ->
          case decode(content) do
            {:ok, %{"providers" => providers}} when is_list(providers) ->
              parse_providers(providers)

            {:ok, data} ->
              Logger.warning("Invalid providers config format: #{inspect(data)}")
              []

            {:error, reason} ->
              Logger.error("Failed to decode providers config: #{inspect(reason)}")
              []
          end

        {:error, reason} ->
          Logger.error("Failed to read providers config: #{inspect(reason)}")
          []
      end
    else
      Logger.info("Providers config file not found, creating default")
      create_default_config()
      []
    end
  end

  @doc "Save providers to config file"
  def save_providers(providers) do
    ensure_aibrain_dir()

    data = %{
      "providers" =>
        Enum.map(providers, fn p ->
          %{
            "name" => p.name,
            "api_key" => p.api_key,
            "base_url" => p.base_url,
            "chat_url" => p.chat_url,
            "fetch_models_url" => p.fetch_models_url,
            "enabled" => p.enabled,
            "models" => p.models || %{}
          }
        end)
    }

    file = providers_file()

    case encode(data) do
      {:ok, content} ->
        File.write!(file, content)
        {:ok, :saved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Load cached models for a provider"
  def load_cached_models(provider_name) do
    file = cached_models_file(provider_name)

    if File.exists?(file) do
      case File.read(file) do
        {:ok, content} ->
          case decode(content) do
            {:ok, %{"models" => models}} when is_list(models) ->
              {:ok, models}

            _ ->
              {:error, :invalid_format}
          end

        {:error, _} ->
          {:error, :file_read_error}
      end
    else
      {:error, :not_found}
    end
  end

  @doc "Save cached models for a provider"
  def save_cached_models(provider_name, models) do
    cache_dir = provider_cache_dir(provider_name)
    File.mkdir_p!(cache_dir)

    data = %{
      "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "models" => models
    }

    file = cached_models_file(provider_name)

    case encode(data) do
      {:ok, content} ->
        File.write!(file, content)
        {:ok, :saved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @cache_dir_global "cache"

  @doc "Get the global cache file path (~/.aibrain/cache/models.json)"
  def global_models_file do
    Path.join([aibrain_dir(), @cache_dir_global, "models.json"])
  end

  @doc "Load global models from merged cache (models.json contains both models + providers)"
  def load_global_models do
    file = global_models_file()

    if File.exists?(file) do
      case File.read(file) do
        {:ok, content} ->
          case decode(content) do
            {:ok, %{"models" => models}} when is_list(models) ->
              {:ok, models}

            {:ok, %{"providers" => _providers}} ->
              # Legacy file that only has providers
              {:ok, []}

            _ ->
              {:error, :invalid_format}
          end

        {:error, _} ->
          {:error, :file_read_error}
      end
    else
      {:error, :not_found}
    end
  end

  def load_openrouter_providers do
    file = global_models_file()

    if File.exists?(file) do
      case File.read(file) do
        {:ok, content} ->
          case decode(content) do
            {:ok, %{"providers" => providers}} when is_list(providers) ->
              {:ok, providers}

            _ ->
              {:error, :invalid_format}
          end

        {:error, _} ->
          {:error, :file_read_error}
      end
    else
      {:error, :not_found}
    end
  end

  @doc "Save merged global cache (models + provider metadata)"
  def save_global_models(models, providers \\ []) do
    cache_dir = Path.join(aibrain_dir(), @cache_dir_global)
    File.mkdir_p!(cache_dir)

    data = %{
      "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "models" => models,
      "providers" => providers
    }

    file = global_models_file()

    case encode(data) do
      {:ok, content} ->
        File.write!(file, content)
        {:ok, :saved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get preset providers (hardcoded)"
  def preset_providers do
    [
      %{
        "name" => "openai",
        "base_url" => "https://api.openai.com/v1",
        "chat_url" => "https://api.openai.com/v1/chat/completions",
        "fetch_models_url" => "https://api.openai.com/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "anthropic",
        "base_url" => "https://api.anthropic.com",
        "chat_url" => "https://api.anthropic.com/v1/messages",
        "fetch_models_url" => nil,
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "deepseek",
        "base_url" => "https://api.deepseek.com/v1",
        "chat_url" => "https://api.deepseek.com/v1/chat/completions",
        "fetch_models_url" => "https://api.deepseek.com/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "google",
        "base_url" => "https://generativelanguage.googleapis.com/v1beta",
        "chat_url" => nil,
        "fetch_models_url" => "https://generativelanguage.googleapis.com/v1beta/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "moonshot",
        "base_url" => "https://api.moonshot.cn/v1",
        "chat_url" => "https://api.moonshot.cn/v1/chat/completions",
        "fetch_models_url" => "https://api.moonshot.cn/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "zhipu",
        "base_url" => "https://open.bigmodel.cn/api/paas/v4",
        "chat_url" => "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        "fetch_models_url" => "https://open.bigmodel.cn/api/paas/v4/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "qwen",
        "base_url" => "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "chat_url" => "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        "fetch_models_url" => "https://dashscope.aliyuncs.com/compatible-mode/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "volcengine",
        "base_url" => "https://ark.cn-beijing.volces.com/api/v3",
        "chat_url" => "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
        "fetch_models_url" => "https://ark.cn-beijing.volces.com/api/v3/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "qianfan",
        "base_url" => "https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop",
        "chat_url" => nil,
        "fetch_models_url" => nil,
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "baichuan",
        "base_url" => "https://api.baichuan-ai.com/v1",
        "chat_url" => "https://api.baichuan-ai.com/v1/chat/completions",
        "fetch_models_url" => "https://api.baichuan-ai.com/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "minimax",
        "base_url" => "https://api.minimax.chat/v1",
        "chat_url" => "https://api.minimax.chat/v1/text/chatcompletion_v2",
        "fetch_models_url" => "https://api.minimax.chat/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "mistral",
        "base_url" => "https://api.mistral.ai/v1",
        "chat_url" => "https://api.mistral.ai/v1/chat/completions",
        "fetch_models_url" => "https://api.mistral.ai/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "siliconflow",
        "base_url" => "https://api.siliconflow.cn/v1",
        "chat_url" => "https://api.siliconflow.cn/v1/chat/completions",
        "fetch_models_url" => "https://api.siliconflow.cn/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "openrouter",
        "base_url" => "https://openrouter.ai/api/v1",
        "chat_url" => "https://openrouter.ai/api/v1/chat/completions",
        "fetch_models_url" => "https://openrouter.ai/api/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "groq",
        "base_url" => "https://api.groq.com/openai/v1",
        "chat_url" => "https://api.groq.com/openai/v1/chat/completions",
        "fetch_models_url" => "https://api.groq.com/openai/v1/models",
        "api_key" => nil,
        "enabled" => false
      },
      %{
        "name" => "together",
        "base_url" => "https://api.together.xyz/v1",
        "chat_url" => "https://api.together.xyz/v1/chat/completions",
        "fetch_models_url" => "https://api.together.xyz/v1/models",
        "api_key" => nil,
        "enabled" => false
      }
    ]
  end

  # Private helpers

  defp parse_providers(providers_list) do
    Enum.map(providers_list, fn p ->
      %AIBrain.Provider.Info{
        name: p["name"],
        api_key: p["api_key"],
        base_url: p["base_url"],
        chat_url: p["chat_url"],
        fetch_models_url: p["fetch_models_url"],
        priority: 100,
        enabled: p["enabled"] || false,
        models: migrate_models(p)
      }
    end)
  end

  # Backward compat: merge old enabled_models + manual_models into unified models map.
  defp migrate_models(%{"models" => models}) when is_map(models) do
    models
  end

  defp migrate_models(p) do
    enabled = p["enabled_models"] || []
    manual = p["manual_models"] || %{}

    # Start with manual_models entries
    models =
      Enum.reduce(manual, %{}, fn {name, meta}, acc ->
        Map.put(acc, name, normalize_model_meta(meta, name in enabled))
      end)

    # Add enabled_models entries not already in manual_models
    Enum.reduce(enabled, models, fn name, acc ->
      if Map.has_key?(acc, name) do
        acc
      else
        Map.put(acc, name, default_model_meta(name))
      end
    end)
  end

  defp normalize_model_meta(meta, enabled?) when is_map(meta) do
    %{
      "enabled" => enabled?,
      "context_window" => meta["context_window"] || meta[:context_window],
      "max_output_tokens" => meta["max_output_tokens"] || meta[:max_output_tokens],
      "type" => meta["type"] || meta[:type] || "text",
      "types" => meta["types"] || meta[:types] || ["text"],
      "input_modalities" => meta["input_modalities"] || meta[:input_modalities] || ["text"],
      "output_modalities" => meta["output_modalities"] || meta[:output_modalities] || ["text"],
      "description" => meta["description"] || meta[:description] || "",
      "source" => "manual"
    }
  end

  defp normalize_model_meta(name, enabled?) when is_binary(name) do
    default_model_meta(name) |> Map.put("enabled", enabled?)
  end

  defp default_model_meta(name) do
    %{
      "enabled" => true,
      "context_window" => nil,
      "max_output_tokens" => nil,
      "type" => "text",
      "types" => ["text"],
      "input_modalities" => ["text"],
      "output_modalities" => ["text"],
      "description" => name,
      "source" => "manual"
    }
  end

  defp create_default_config do
    ensure_aibrain_dir()

    data = %{"providers" => preset_providers()}

    case encode(data) do
      {:ok, content} ->
        File.write!(providers_file(), content)
        Logger.info("Created default providers config at #{providers_file()}")

      {:error, reason} ->
        Logger.error("Failed to create default config: #{inspect(reason)}")
    end
  end
end
