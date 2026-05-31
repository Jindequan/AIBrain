defmodule AIBrain.LLM.Provider do
  @moduledoc """
  Provider management integration with ReqLLM.

  This module provides a unified interface to ReqLLM providers and local
  configuration. It replaces the previous scattered Provider.Info + Registry + FileBackend system.

  ## Architecture

  ReqLLM provides:
  - Built-in provider definitions for 22+ providers
  - Automatic model registry from models.dev (665+ models)
  - Standardized request/response format
  - Automatic key management via ReqLLM.put_key/2

  AIBrain adds:
  - Local model enable/disable toggles
  - Priority-based provider routing
  - Cost tracking and billing
  - Backward compatibility with existing APIs
  """

  require Logger

  # ── Provider Info ──────────────────────────────────────────

  @doc """
  Get all available providers from ReqLLM.

  Returns a list of provider atoms: :anthropic, :openai, :google, etc.
  """
  def list_providers do
    # ReqLLM doesn't expose a public list_providers function,
    # so we return a hardcoded list of known providers.
    [
      :anthropic, :openai, :google, :google_vertex, :azure, :aws_bedrock,
      :groq, :xai, :openrouter, :cerebras, :fireworks_ai, :meta, 
      :mistral, :together, :ollama, :vllm, :nearai, :zai, :zai_coder,
      :zenmux, :venetian, :alibaba, :alibaba_cn, :minimax, :baichuan, :qianfan
    ]
  end

  @doc """
  Get detailed metadata for a specific provider.

  Returns provider information including name, models, and capabilities.
  """
  def get_provider(provider_atom) when is_atom(provider_atom) do
    {:ok, %{
      name: Atom.to_string(provider_atom),
      provider: provider_atom,
      base_url: infer_base_url(provider_atom),
      fetch_models_url: nil,
      chat_url: nil
    }}
  rescue
    _e -> {:error, :invalid_provider}
  end

  def get_provider(provider_name) when is_binary(provider_name) do
    provider_name
    |> String.to_atom()
    |> get_provider()
  rescue
    _e -> {:error, :invalid_provider}
  end

  # Helper to infer base URL for common providers
  defp infer_base_url(provider_atom) do
    case provider_atom do
      :openai -> "https://api.openai.com/v1"
      :anthropic -> "https://api.anthropic.com"
      :google -> "https://generativelanguage.googleapis.com/v1beta"
      :groq -> "https://api.groq.com/openai/v1"
      :openrouter -> "https://openrouter.ai/api/v1"
      :mistral -> "https://api.mistral.ai/v1"
      :together -> "https://api.together.xyz/v1"
      _ -> nil
    end
  end

  # ── Model Handling ─────────────────────────────────────────

  @doc """
  List all models for a provider.

  Queries LLMDB for the provider's model catalog.
  Each model includes metadata: context_window, capabilities, pricing, etc.
  """
  def list_models(provider) do
    with {:ok, provider_atom} <- normalize_provider(provider) do
      try do
        models = LLMDB.models(provider_atom)
        if models == [] or is_list(models) do
          {:ok, models}
        else
          {:ok, []}
        end
      rescue
        _ -> {:ok, []}
      end
    end
  end

  @doc """
  Get a specific model definition.

  Model can be:
  - "provider:model" string format
  - {provider, model_id} tuple
  - %LLMDB.Model{} struct
  """
  def get_model(model_spec) do
    case ReqLLM.model(model_spec) do
      {:ok, model} -> {:ok, model}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get model with required metadata validation.

  Raises if the model spec is invalid or missing required information.
  """
  def get_model!(model_spec) do
    ReqLLM.model!(model_spec)
  end

  # ── Key Management ─────────────────────────────────────────

  @doc """
  Store an API key for a provider.

  Keys can be provided per-request or stored here. ReqLLM checks:
  per-request → stored → env vars → .env files
  """
  def put_api_key(provider, api_key) when is_binary(api_key) do
    provider_atom = normalize_provider(provider) |> elem(1)
    key_name = provider_key_name(provider_atom)
    ReqLLM.put_key(key_name, api_key)
    # Persist key to disk so it survives restarts
    AIBrain.Config.ProviderConfig.set_api_key(Atom.to_string(provider_atom), api_key)
    :ok
  end

  @doc """
  Retrieve a stored API key for a provider.

  Returns {key, source} where source is :stored, :env, :dotenv, or nil.
  """
  def get_api_key(provider) do
    provider_atom = normalize_provider(provider) |> elem(1)
    key_name = provider_key_name(provider_atom)
    provider_name = Atom.to_string(provider_atom)

    # Check ReqLLM first (in-memory, set during this session)
    key = ReqLLM.get_key(key_name)

    cond do
      key && key != "" ->
        {:ok, key, :stored}

      true ->
        # Fall back to persisted config (survives restarts)
        persisted = AIBrain.Config.ProviderConfig.get_api_key(provider_name)
        if persisted && persisted != "" do
          # Restore into ReqLLM for this session
          ReqLLM.put_key(key_name, persisted)
          {:ok, persisted, :persisted}
        else
          {:error, :not_found}
        end
    end
  end

  @doc """
  Check if a provider has a stored API key.
  """
  def has_api_key?(provider) do
    provider_atom = normalize_provider(provider) |> elem(1)
    key_name = provider_key_name(provider_atom)

    case ReqLLM.get_key(key_name) do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  # ── Active Provider Selection ──────────────────────────────

  @doc """
  Get all enabled providers (configured with API keys).
  """
  def active_providers do
    list_providers()
    |> Enum.filter(&has_api_key?/1)
  end

  @doc """
  Select a provider for a request.

  Implements priority-based routing:
  1. Explicitly requested provider (if enabled)
  2. First active provider (by ReqLLM priority)
  3. nil (error case)
  """
  def select_provider(requested \\ nil) do
    cond do
      is_nil(requested) ->
        active_providers() |> List.first()

      is_binary(requested) or is_atom(requested) ->
        provider_atom = normalize_provider(requested) |> elem(1)

        if has_api_key?(provider_atom) do
          {:ok, provider_atom}
        else
          {:error, :provider_not_configured}
        end

      true ->
        {:error, :invalid_provider}
    end
  end

  # ── Model Resolution ──────────────────────────────────────

  @doc """
  Resolve a model request to an actual model spec.

  Handles:
  - "provider:model" format
  - {provider, model} tuple
  - "default" → system default or first available
  - nil → system default
  """
  def resolve_model(model_request \\ nil, provider_hint \\ nil)

  def resolve_model(nil, provider_hint) do
    resolve_model("default", provider_hint)
  end

  def resolve_model("default", _provider_hint) do
    {provider_name, model_name} = AIBrain.Data.SystemSetting.default_llm_model()
    {:ok, ReqLLM.model!("#{provider_name}:#{model_name}")}
  end

  def resolve_model(model_request, _provider_hint) when is_binary(model_request) or is_tuple(model_request) do
    case ReqLLM.model(model_request) do
      {:ok, model} -> {:ok, model}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Capabilities ───────────────────────────────────────────

  @doc """
  Check if a model supports a specific capability.

  Capabilities: :text, :vision, :streaming, :function_calling, :structured_output, etc.
  """
  def supports_capability?(model_spec, capability) do
    case get_model(model_spec) do
      {:ok, model} ->
        case capability do
          :text -> true  # All models support text
          :vision -> Map.get(model, :vision, false)
          :audio -> Map.get(model, :audio, false)
          :streaming -> true  # ReqLLM supports streaming for all providers
          :function_calling -> Map.get(model, :tool_use, false)
          :structured_output -> Map.get(model, :structured_output, false)
          _ -> false
        end

      {:error, _reason} ->
        false
    end
  end

  @doc """
  Get context window size for a model.

  Returns integer token count, or nil if unknown.
  """
  def context_window(model_spec) do
    case get_model(model_spec) do
      {:ok, model} -> Map.get(model, :context_window)
      {:error, _reason} -> nil
    end
  end

  @doc """
  Get max output tokens for a model.

  Returns integer token count, or nil if unknown.
  """
  def max_output_tokens(model_spec) do
    case get_model(model_spec) do
      {:ok, model} -> Map.get(model, :max_output_tokens)
      {:error, _reason} -> nil
    end
  end

  # ── Cost & Usage ───────────────────────────────────────────

  @doc """
  Get pricing info for a model.

  Returns %{input_cost: float, output_cost: float} per 1M tokens.
  """
  def get_pricing(model_spec) do
    case get_model(model_spec) do
      {:ok, model} ->
        %{
          input_cost: Map.get(model, :input_cost),
          output_cost: Map.get(model, :output_cost)
        }

      {:error, _reason} ->
        %{input_cost: nil, output_cost: nil}
    end
  end

  # ── Private Helpers ────────────────────────────────────────

  defp normalize_provider(provider) when is_atom(provider) do
    {:ok, provider}
  end

  defp normalize_provider(provider) when is_binary(provider) do
    try do
      {:ok, String.to_atom(provider)}
    rescue
      _e -> {:error, :invalid_provider}
    end
  end

  defp normalize_provider(_), do: {:error, :invalid_provider}

  defp provider_key_name(provider_atom) do
    # Map provider atoms to ReqLLM key names
    # e.g., :openai -> :openai_api_key, :anthropic -> :anthropic_api_key
    :"#{provider_atom}_api_key"
  end

end
