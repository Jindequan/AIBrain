defmodule AIBrain.Provider.Catalog do
  @moduledoc """
  Provider / model catalog backed by req_llm and LLMDB.

  Replaces the old OpenRouter-only catalog and hardcoded provider lists.
  """

  @doc """
  All registered provider IDs (atoms) from req_llm.
  """
  def provider_ids, do: ReqLLM.Providers.list()

  @doc """
  Structured provider metadata for every registered provider.
  """
  def provider_entries do
    Enum.map(provider_ids(), fn id ->
      module = ReqLLM.Providers.get!(id)

      %{
        id: id,
        name: id |> Atom.to_string(),
        display_name: display_name(module),
        base_url: default_base_url(module),
        env_key: default_env_key(module)
      }
    end)
  end

  @doc """
  All models from LLMDB across all registered providers.
  Returns list of maps with id, name, provider, context_length, modalities.
  """
  def list_models do
    provider_ids()
    |> Enum.flat_map(&models_for_provider/1)
  end

  @doc """
  Models for a specific provider.
  """
  def models_for_provider(provider_id) do
    provider_str = Atom.to_string(provider_id)

    LLMDB.models(provider_id)
    |> Enum.map(fn model ->
      %{
        "id" => model.id,
        "name" => model.name || model.id,
        "full_id" => "#{provider_str}:#{model.id}",
        "provider" => provider_str,
        "context_length" => get_in(model, [Access.key(:limits), Access.key(:context)]),
        "max_output_tokens" => max_output(model),
        "input_modalities" => modality_list(model, :input),
        "output_modalities" => modality_list(model, :output),
        "description" => description(model)
      }
    end)
  rescue
    e ->
      require Logger
      Logger.error("Catalog: failed to list models: #{Exception.message(e)}")
      []
  end

  # -- private --

  defp name(model), do: model.name || model.id

  defp description(model) do
    (model.family || model.name || model.id || "")
  end

  defp max_output(model) do
    get_in(model, [Access.key(:limits), Access.key(:output)])
  end

  defp modality_list(model, direction) do
    case get_in(model, [Access.key(:modalities), direction]) do
      nil -> ["text"]
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> ["text"]
    end
  end

  defp display_name(module) do
    if function_exported?(module, :display_name, 0) do
      module.display_name()
    else
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")
    end
  end

  defp default_base_url(module) do
    if function_exported?(module, :default_base_url, 0) do
      module.default_base_url()
    end
  end

  defp default_env_key(module) do
    if function_exported?(module, :default_env_key, 0) do
      module.default_env_key()
    end
  end
end
