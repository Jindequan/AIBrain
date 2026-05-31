defmodule AIBrain.Provider.Info do
  @moduledoc """
  Provider configuration struct.

  Stored in ~/.aibrain/providers.json.
  Fetched models cached in ~/.aibrain/cache/providers/{name}/models.json

  ## Models map

  Each provider has a `models` map: model_name → metadata.
  Metadata keys:
    - "enabled" — boolean, user-activated
    - "context_window" — integer, max input tokens
    - "max_output_tokens" — integer, max output tokens
    - "type" — primary type ("text", "image", "video", "audio")
    - "types" — list of supported types
    - "input_modalities" — list
    - "output_modalities" — list
    - "description" — human-readable
    - "source" — "fetched" | "manual", how the model was added
  """

  @enforce_keys [:name, :priority]
  defstruct [
    :name,
    :api_key,
    :base_url,
    :fetch_models_url,
    :chat_url,
    :priority,
    :enabled,
    models: %{}
  ]

  @type model_meta :: %{
          String.t() => any()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          api_key: String.t() | nil,
          base_url: String.t(),
          fetch_models_url: String.t() | nil,
          chat_url: String.t() | nil,
          priority: integer(),
          enabled: boolean(),
          models: %{String.t() => model_meta()}
        }

  # ── Model helpers ───────────────────────────────────────────

  @doc "List all enabled model names for this provider."
  def enabled_models(%__MODULE__{models: models}) do
    models
    |> Enum.filter(fn {_, m} -> m["enabled"] end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Get metadata for a specific model."
  def model_meta(%__MODULE__{models: models}, model_name) do
    Map.get(models, model_name, %{})
  end

  @doc "Check if a model is enabled on this provider."
  def model_enabled?(%__MODULE__{models: models}, model_name) do
    Map.get(models, model_name, %{})["enabled"] == true
  end

  @doc "Does this provider have the given model (enabled or not)?"
  def has_model?(%__MODULE__{models: models}, model_name) do
    Map.has_key?(models, model_name)
  end

  @doc "Get context_window for a model, falling back to 128000."
  def model_context_window(%__MODULE__{models: models}, model_name) do
    case Map.get(models, model_name, %{}) do
      %{"context_window" => n} when is_integer(n) and n > 0 -> n
      _ -> 128_000
    end
  end

  @doc "Get max_output_tokens for a model, or nil if not set."
  def model_max_output_tokens(%__MODULE__{models: models}, model_name) do
    case Map.get(models, model_name, %{}) do
      %{"max_output_tokens" => n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end
  end

  # ── Endpoint ────────────────────────────────────────────────

  @doc "Get the chat endpoint URL for this provider"
  def chat_endpoint(%__MODULE__{chat_url: nil, name: name})
      when name in ["google", "qianfan"] do
    nil
  end

  def chat_endpoint(%__MODULE__{chat_url: nil, base_url: nil}), do: nil

  def chat_endpoint(%__MODULE__{chat_url: nil, base_url: base_url}) do
    "#{base_url}/chat/completions"
  end

  def chat_endpoint(%__MODULE__{chat_url: chat_url}), do: chat_url

  @doc """
  Return an endpoint shape consumed by LLM adapters.
  """
  def get_endpoint(%__MODULE__{base_url: nil, chat_url: nil}, _protocol), do: nil

  def get_endpoint(%__MODULE__{} = provider, _protocol) do
    case chat_endpoint(provider) do
      nil -> nil
      url ->
        # Fetch API key dynamically — the Info struct may be stale from startup
        key =
          case AIBrain.LLM.Provider.get_api_key(provider.name) do
            {:ok, k, _} -> k
            _ -> provider.api_key
          end

        %{
          url: url,
          base_url: provider.base_url,
          api_key: key
        }
    end
  end

  @doc "Check if this provider supports fetching models via API"
  def supports_model_fetch?(%__MODULE__{fetch_models_url: nil}), do: false
  def supports_model_fetch?(%__MODULE__{fetch_models_url: _url}), do: true

  @doc "Get the API client configuration for HTTP requests"
  def api_config(%__MODULE__{api_key: nil}), do: %{}
  def api_config(%__MODULE__{api_key: key}), do: %{Authorization: "Bearer #{key}"}

  # ── Model resolution ──────────────────────────────────────

  @doc """
  Resolve a requested model name to an actual model on the given provider.

  When "default" or nil is requested, looks up the system default model and
  returns it if it belongs to this provider. Otherwise falls back to the first
  enabled model on the provider.
  """
  def map_model(provider, requested_model)

  def map_model(_provider, nil), do: "default"
  def map_model(_provider, ""), do: "default"

  def map_model(provider, "default") do
    # Try system default first
    case AIBrain.Data.SystemSetting.default_llm_model() do
      {provider_name, model_name} when is_binary(provider_name) and is_binary(model_name) ->
        if provider_name == provider.name, do: model_name, else: first_enabled_or_default(provider)
      _ ->
        first_enabled_or_default(provider)
    end
  end

  def map_model(_provider, requested_model), do: requested_model

  defp first_enabled_or_default(provider) do
    case enabled_models(provider) do
      [first | _] -> first
      [] -> "default"
    end
  end

  @doc "Returns the model name for a scene category (lite, normal, image, video, audio)."
  def get_model_for_scene(provider, scene) when is_atom(scene) do
    get_model_for_scene(provider, to_string(scene))
  end

  def get_model_for_scene(provider, scene) when is_binary(scene) do
    case AIBrain.Data.SystemSetting.default_model(scene) do
      {provider_name, model_name} when is_binary(provider_name) and is_binary(model_name) ->
        if provider_name == provider.name, do: model_name, else: nil
      _ ->
        nil
    end
  end

  def get_model_for_scene(_provider, _scene), do: nil
end
