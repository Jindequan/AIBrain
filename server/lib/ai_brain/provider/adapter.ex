defmodule AIBrain.Provider.Adapter do
  @moduledoc """
  Compatibility adapter between the old Provider system and ReqLLM.

  Converts between:
  - ReqLLM provider specs and AIBrain.Provider.Info structs
  - ReqLLM models and AIBrain local model configs

  This enables gradual migration without breaking existing code.
  """

  require Logger

  alias AIBrain.Provider.Info
  alias AIBrain.Config.ProviderConfig
  alias AIBrain.LLM.Provider, as: LLMProvider

  @doc """
  Convert a ReqLLM provider to an AIBrain Provider.Info struct.

  Merges ReqLLM data with local configuration.
  """
  def to_provider_info(provider_atom) when is_atom(provider_atom) do
    provider_name = Atom.to_string(provider_atom)

    case LLMProvider.get_provider(provider_atom) do
      {:ok, provider_info} ->
        local_cfg = ProviderConfig.get_provider_config(provider_name)

        api_key =
          case LLMProvider.get_api_key(provider_atom) do
            {:ok, key, _source} -> key
            _ -> nil
          end

        %Info{
          name: provider_name,
          api_key: api_key,
          base_url: Map.get(local_cfg, "base_url") || provider_info.base_url || catalog_base_url(provider_atom),
          fetch_models_url: provider_info.fetch_models_url,
          chat_url: provider_info.chat_url,
          priority: Map.get(local_cfg, "priority", 0),
          enabled: Map.get(local_cfg, "enabled", true),
          models: build_models_map(provider_atom, local_cfg)
        }

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Convert an AIBrain Provider.Info struct to ReqLLM format.

  Applies key management and config updates.
  """
  def to_req_llm_provider(%Info{name: name, api_key: api_key, base_url: base_url, priority: priority, enabled: enabled}) do
    # Store API key in ReqLLM if provided
    if api_key && String.length(String.trim(api_key)) > 0 do
      LLMProvider.put_api_key(name, api_key)
    end

    # Update local config
    ProviderConfig.update_provider_config(name, %{
      "priority" => priority,
      "enabled" => enabled,
      "base_url" => base_url
    })

    {:ok, String.to_atom(name)}
  rescue
    e ->
      Logger.error("Failed to convert provider to req_llm format: #{inspect(e)}")
      {:error, :conversion_failed}
  end

  # ── Model Conversion ───────────────────────────────────────

  @doc """
  Build a models map for a provider, merging ReqLLM data with local config.
  """
  def build_models_map(provider_atom, _local_cfg) do
    try do
      LLMDB.models(provider_atom)
      |> Enum.reduce(%{}, fn model, acc ->
        Map.put(acc, model.id, %{
          "enabled" => true,
          "context_window" => get_in(model, [Access.key(:limits), Access.key(:context)]),
          "max_output_tokens" => get_in(model, [Access.key(:limits), Access.key(:output)]),
          "type" => "text",
          "types" => ["text"],
          "input_modalities" => Enum.map(get_in(model, [Access.key(:modalities), :input]) || ["text"], &to_string/1),
          "output_modalities" => Enum.map(get_in(model, [Access.key(:modalities), :output]) || ["text"], &to_string/1),
          "description" => model.name || model.id,
          "source" => "llmdb"
        })
      end)
    rescue
      _ -> %{}
    end
  end

  @doc """
  Check if a model is enabled in local config.
  """
  def model_enabled?(provider_name, model_name) do
    ProviderConfig.model_enabled?(provider_name, model_name)
  end

  @doc """
  Get enabled models for a provider from local config.
  """
  def enabled_models(provider_name) do
    ProviderConfig.enabled_models(provider_name)
  end

  # ── Migration Helpers ──────────────────────────────────────

  @doc """
  Migrate old providers.json to new ReqLLM + local config format.

  Reads the old Provider.Info entries and imports them into:
  - ReqLLM API key storage
  - AIBrain local config (priorities, models enabled/disabled)
  """
  def migrate_old_config do
    Logger.info("Starting provider config migration to ReqLLM...")

    case AIBrain.Config.FileBackend.load_providers() do
      [] ->
        Logger.info("No legacy providers found, skipping migration")
        :ok

      legacy_providers ->
        Enum.each(legacy_providers, fn provider ->
          Logger.info("Migrating provider: #{provider.name}")

          # Store API key
          if provider.api_key && String.length(String.trim(provider.api_key)) > 0 do
            LLMProvider.put_api_key(provider.name, provider.api_key)
          end

          # Store local config
          ProviderConfig.update_provider_config(provider.name, %{
            "priority" => provider.priority,
            "enabled" => provider.enabled,
            "base_url" => provider.base_url,
            "models" => migrate_models(provider.models)
          })

          Logger.info("Migrated provider: #{provider.name}")
        end)

        Logger.info("Provider config migration completed")
        :ok
    end
  rescue
    e ->
      Logger.error("Provider migration failed: #{inspect(e)}")
      {:error, e}
  end

  # ── Private Helpers ──────────────────────────────────────

  defp catalog_base_url(provider_atom) do
    try do
      module = ReqLLM.Providers.get!(provider_atom)

      if function_exported?(module, :default_base_url, 0) do
        module.default_base_url()
      end
    rescue
      _ -> nil
    end
  end

  defp migrate_models(models_map) when is_map(models_map) do
    models_map
    |> Enum.reduce(%{}, fn {model_name, model_cfg}, acc ->
      migrated = %{
        "enabled" => Map.get(model_cfg, "enabled", true)
      }

      Map.put(acc, model_name, migrated)
    end)
  end

  defp migrate_models(_), do: %{}
end
