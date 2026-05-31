defmodule AIBrain.Data.SystemSetting do
  @moduledoc """
  System-wide settings stored in database.
  Used for storing default model configuration and other system-level preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Repo

  @categories ["lite", "normal", "image", "video", "audio"]

  @primary_key {:key, :string, autogenerate: false}
  schema "system_settings" do
    field(:value, :string)
    timestamps(updated_at: false)
  end

  # ── Generic key-value ──

  @doc "Get a setting value by key"
  def get(key) do
    case Repo.get(__MODULE__, key) do
      nil -> {:error, :not_found}
      setting -> {:ok, setting.value}
    end
  end

  @doc "Set a setting value (upsert)"
  def set(key, value) do
    %__MODULE__{}
    |> changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value]],
      conflict_target: [:key]
    )
  end

  @doc "Get all settings as a map"
  def all do
    Repo.all(__MODULE__)
    |> Enum.map(fn s -> {s.key, s.value} end)
    |> Map.new()
  end

  # ── Category-aware default models ──

  @doc "Get default model for a given category"
  def default_model(category) when category in @categories do
    case get("default_model_#{category}") do
      {:ok, value} ->
        case Jason.decode(value) do
          {:ok, %{"provider" => p, "model" => m}} when is_binary(p) and is_binary(m) ->
            {p, m}

          _ ->
            {:error, :not_found}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  def default_model(_), do: {:error, :invalid_category}

  @doc "Set default model for a given category"
  def set_default_model(category, {provider, model}) when category in @categories do
    result = set("default_model_#{category}", Jason.encode!(%{provider: provider, model: model}))
    # Keep default_llm_model in sync for LLM categories.
    if category in ~w(normal lite) do
      set("default_llm_model", Jason.encode!(%{provider: provider, model: model}))
    end
    result
  end

  def set_default_model(_, _), do: {:error, :invalid_category}

  # ── Global LLM default ──

  @doc """
  Get the global default LLM model (provider + model).

  Falls back to category defaults if not explicitly set.
  """
  def default_llm_model do
    try do
      case get("default_llm_model") do
        {:ok, value} ->
          case Jason.decode(value) do
            {:ok, %{"provider" => p, "model" => m}} when is_binary(p) and is_binary(m) ->
              {p, m}

            _ ->
              fallback_default()
          end

        {:error, _} ->
          fallback_default()
      end
    rescue
      _ -> fallback_default()
    end
  end

  defp fallback_default do
    case default_model("normal") do
      {p, m} when is_binary(p) and is_binary(m) -> {p, m}
      _ ->
        case default_model("lite") do
          {p, m} when is_binary(p) and is_binary(m) -> {p, m}
          _ -> {"openai", "gpt-4o"}  # hardcoded ultimate fallback
        end
    end
  rescue
    _ -> {"openai", "gpt-4o"}
  end

  @doc "Set the global default LLM model."
  def set_default_llm_model({provider, model}) do
    set("default_llm_model", Jason.encode!(%{provider: provider, model: model}))
  end

  @doc "Get all default models as a map"
  def all_default_models do
    @categories
    |> Enum.reduce(%{}, fn cat, acc ->
      case default_model(cat) do
        {p, m} when is_binary(p) and is_binary(m) -> Map.put(acc, cat, %{provider: p, model: m})
        _ -> acc
      end
    end)
  end

  # ── Changeset ──

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
