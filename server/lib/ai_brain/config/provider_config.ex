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

  @doc """
  Enable a model for a provider.

  If `enabled_models` is nil (all enabled by default), this is a no-op.
  If it's an explicit list, the model is added.
  """
  def enable_model(provider_name, model_name)
      when is_binary(provider_name) and is_binary(model_name) do
    config = load_config()
    providers = Map.get(config, "providers", %{})
    provider_cfg = Map.get(providers, provider_name, %{})

    case Map.get(provider_cfg, "enabled_models") do
      nil ->
        {:ok, :all}

      models when is_list(models) ->
        updated = [model_name | models] |> Enum.uniq()
        new_cfg = Map.put(provider_cfg, "enabled_models", updated)
        new_config = Map.put(config, "providers", Map.put(providers, provider_name, new_cfg))
        save_config(new_config)
        {:ok, :updated}

      _ ->
        {:ok, :all}
    end
  end

  @doc """
  Disable a model for a provider.

  If `enabled_models` is nil (all enabled), this materializes the list
  from the catalog first, then removes the model.
  If it's already an explicit list, the model is removed.
  """
  def disable_model(provider_name, model_name)
      when is_binary(provider_name) and is_binary(model_name) do
    config = load_config()
    providers = Map.get(config, "providers", %{})
    provider_cfg = Map.get(providers, provider_name, %{})

    updated_list =
      case Map.get(provider_cfg, "enabled_models") do
        nil ->
          provider_atom = String.to_atom(provider_name)
          all_models = LLMDB.models(provider_atom) |> Enum.map(& &1.id)
          List.delete(all_models, model_name)

        models when is_list(models) ->
          List.delete(models, model_name)

        _ ->
          []
      end

    new_cfg = Map.put(provider_cfg, "enabled_models", updated_list)
    new_config = Map.put(config, "providers", Map.put(providers, provider_name, new_cfg))
    save_config(new_config)
    {:ok, :updated}
  end

  @doc """
  Get enabled models for a provider.

  Returns `:all` when no explicit list is set (all models enabled by default),
  or a list of model IDs that are explicitly enabled.
  """
  def enabled_models(provider_name) when is_binary(provider_name) do
    cfg = get_provider_config(provider_name)

    case Map.get(cfg, "enabled_models") do
      nil -> :all
      models when is_list(models) -> models
      _ -> :all
    end
  end

  @doc "Check if a model is enabled for a provider."
  def model_enabled?(provider_name, model_name)
      when is_binary(provider_name) and is_binary(model_name) do
    case enabled_models(provider_name) do
      :all -> true
      models -> model_name in models
    end
  end

  @doc """
  Convenience: toggle a "provider:model" string.
  """
  def toggle_model(model_id, enabled) when is_binary(model_id) and is_boolean(enabled) do
    case String.split(model_id, ":", parts: 2) do
      [provider, model] ->
        if enabled, do: enable_model(provider, model), else: disable_model(provider, model)

      _ ->
        {:error, :invalid_model_id}
    end
  end

  @doc """
  Convenience: toggle with separate provider and model name.
  """
  def toggle_model(provider_name, model_name, enabled)
      when is_binary(provider_name) and is_binary(model_name) do
    if enabled, do: enable_model(provider_name, model_name), else: disable_model(provider_name, model_name)
  end

  @doc """
  Get all user-configured models across providers.
  Returns list of {provider, model_id} tuples.
  """
  def all_enabled_models do
    load_config()
    |> Map.get("providers", %{})
    |> Enum.flat_map(fn {provider, cfg} ->
      case Map.get(cfg, "enabled_models") do
        nil -> []
        models when is_list(models) -> Enum.map(models, fn m -> {provider, m} end)
        _ -> []
      end
    end)
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
