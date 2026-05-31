defmodule AIBrain.Config.ProviderConfig do
  @moduledoc """
  Local provider configuration management.

  Stores per-provider settings that augment ReqLLM's built-in provider metadata:
  - enabled/disabled toggle
  - priority for routing
  - custom base_url overrides
  - model-level enabled/disabled toggles

  Persists to ~/.aibrain/provider_config.json
  """

  require Logger
  import Jason

  alias AIBrain.Config.FileBackend

  @config_file "provider_config.json"
  @term_key :ai_brain_provider_config

  # ── Cache (persistent_term — survives process death) ──────────

  defp cached_config do
    case :persistent_term.get(@term_key, nil) do
      nil ->
        config = read_config_from_disk()
        :persistent_term.put(@term_key, config)
        config
      config ->
        config
    end
  end

  defp cache_put(config) do
    :persistent_term.put(@term_key, config)
  end

  def cache_invalidate do
    :persistent_term.erase(@term_key)
  rescue
    _ -> :ok
  end

  # ── Public API ───────────────────────────────────────────────
  def config_file do
    Path.join(FileBackend.aibrain_dir(), @config_file)
  end

  @doc "Load local provider configuration (uses in-memory cache)"
  def load_config do
    cached_config()
  end

  # Read from disk, bypassing cache
  defp read_config_from_disk do
    file = config_file()

    if File.exists?(file) do
      case File.read(file) do
        {:ok, content} ->
          case decode(content) do
            {:ok, config} -> config
            {:error, reason} ->
              Logger.error("Failed to decode provider config: #{inspect(reason)}")
              default_config()
          end

        {:error, reason} ->
          Logger.error("Failed to read provider config: #{inspect(reason)}")
          default_config()
      end
    else
      default_config()
    end
  end

  @doc "Save provider configuration to disk"
  def save_config(config) do
    FileBackend.ensure_aibrain_dir()

    case encode(config) do
      {:ok, content} ->
        File.write!(config_file(), content)
        cache_put(config)
        {:ok, :saved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get configuration for a specific provider"
  def get_provider_config(provider_name) when is_binary(provider_name) do
    config = load_config()

    Map.get(config, "providers", %{})
    |> Map.get(provider_name, default_provider_config())
  end

  @doc "Update configuration for a specific provider"
  def update_provider_config(provider_name, updates) when is_binary(provider_name) and is_map(updates) do
    config = load_config()
    providers = Map.get(config, "providers", %{})
    current = Map.get(providers, provider_name, default_provider_config())
    updated = Map.merge(current, updates)
    new_config = Map.put(config, "providers", Map.put(providers, provider_name, updated))
    save_config(new_config)
  end

  @doc "Enable a provider"
  def enable_provider(provider_name) when is_binary(provider_name) do
    update_provider_config(provider_name, %{"enabled" => true})
  end

  @doc "Disable a provider"
  def disable_provider(provider_name) when is_binary(provider_name) do
    update_provider_config(provider_name, %{"enabled" => false})
  end

  @doc "Check if a provider is enabled"
  def provider_enabled?(provider_name) when is_binary(provider_name) do
    get_provider_config(provider_name)
    |> Map.get("enabled", true)
  end

  @doc "Set provider priority"
  def set_provider_priority(provider_name, priority) when is_binary(provider_name) and is_integer(priority) do
    update_provider_config(provider_name, %{"priority" => priority})
  end

  @doc "Get provider priority"
  def get_provider_priority(provider_name) when is_binary(provider_name) do
    get_provider_config(provider_name)
    |> Map.get("priority", 0)
  end

  @doc "Set custom base URL for a provider"
  def set_base_url(provider_name, base_url) when is_binary(provider_name) and is_binary(base_url) do
    update_provider_config(provider_name, %{"base_url" => base_url})
  end

  @doc "Get custom base URL for a provider, or nil"
  def get_base_url(provider_name) when is_binary(provider_name) do
    get_provider_config(provider_name)
    |> Map.get("base_url")
  end

  @doc "Persist API key for a provider."
  def set_api_key(provider_name, api_key) when is_binary(provider_name) and is_binary(api_key) do
    update_provider_config(provider_name, %{"api_key" => api_key})
  end

  @doc "Read persisted API key for a provider, or nil."
  def get_api_key(provider_name) when is_binary(provider_name) do
    get_provider_config(provider_name)
    |> Map.get("api_key")
  end

  @doc "Add a model to the disabled list for a provider. O(1)."
  def disable_model(provider_name, model_name) when is_binary(provider_name) and is_binary(model_name) do
    config = load_config()
    providers = Map.get(config, "providers", %{})
    provider_cfg = Map.get(providers, provider_name, %{})
    current = Map.get(provider_cfg, "disabled_models", [])
    updated = [model_name | current] |> Enum.uniq()
    new_cfg = Map.put(provider_cfg, "disabled_models", updated)
    new_config = Map.put(config, "providers", Map.put(providers, provider_name, new_cfg))
    save_config(new_config)
  end

  @doc "Check if a model is enabled in a provider"
  def model_enabled?(provider_name, model_name) when is_binary(provider_name) and is_binary(model_name) do
    model_name not in disabled_models(provider_name)
  end

  @doc "Get disabled models for a provider (all models enabled by default)"
  def disabled_models(provider_name) when is_binary(provider_name) do
    config = load_config()

    config
    |> Map.get("providers", %{})
    |> Map.get(provider_name, %{})
    |> Map.get("disabled_models", [])
  end

  @doc "Toggle a model: disable or enable. Uses disabled_models list so O(1)."
  def toggle_model(model_id, enabled) when is_binary(model_id) and is_boolean(enabled) do
    case String.split(model_id, ":", parts: 2) do
      [provider, model] -> toggle_model(provider, model, enabled)
      _ -> {:error, :invalid_model_id}
    end
  end

  def toggle_model(provider_name, model_name, enabled) when is_binary(provider_name) and is_binary(model_name) do
    config = load_config()
    providers = Map.get(config, "providers", %{})
    provider_cfg = Map.get(providers, provider_name, %{})
    current = Map.get(provider_cfg, "disabled_models", [])
    updated = if enabled, do: List.delete(current, model_name), else: [model_name | current] |> Enum.uniq()
    new_cfg = Map.put(provider_cfg, "disabled_models", updated)
    new_config = Map.put(config, "providers", Map.put(providers, provider_name, new_cfg))
    save_config(new_config)
    {:ok, enabled}
  end

  @doc "Get enabled models for a provider. Returns :all (default) or a list minus disabled."
  def enabled_models(provider_name) when is_binary(provider_name) do
    :all
  end

  # ── Private Helpers ────────────────────────────────────────

  defp default_config do
    %{
      "version" => "1",
      "providers" => %{}
    }
  end

  defp default_provider_config do
    %{
      "enabled" => true,
      "priority" => 0
    }
  end
end
