defmodule AIBrain.Provider.SmartRouter do
  @moduledoc """
  Cost-aware model selection. Chooses the right model for task complexity,
  then finds the cheapest available provider for that model.

  Reads tier defaults from provider configuration instead of the removed
  database `models` table.
  Returns {:ok, provider, selected_model_name} or {:error, {:all_unavailable, soonest}}.
  """

  require Logger
  alias AIBrain.Provider.Router

  @tiers [:cheap, :mid, :strong, :best]
  @tier_fallback_order %{
    cheap: [:mid, :strong, :best],
    mid: [:cheap, :strong, :best],
    strong: [:mid, :best, :cheap],
    best: [:strong, :mid, :cheap]
  }

  @doc """
  Select the best provider+model for the given loop state.
  Returns {:ok, provider, model_name} or {:error, {:all_unavailable, soonest}}.
  """
  def select(router, state) do
    complexity = assess_complexity(state)
    tier = tier_for(complexity, state.retries)

    Logger.debug(
      "SmartRouter: complexity=#{complexity} tier=#{tier} turn=#{state.turn} retries=#{state.retries}"
    )

    case select_model_by_tier(router, tier) do
      {:ok, provider, model_name} ->
        {:ok, provider, model_name}

      {:error, {:all_unavailable, _soonest}} = error ->
        fallback_tiers = Map.get(@tier_fallback_order, tier, [])
        try_fallback_tiers(router, fallback_tiers, error)
    end
  end

  # -- complexity assessment --

  defp assess_complexity(%{tools: [], turn: 0}), do: :simple
  defp assess_complexity(%{tools: tools, turn: turn}) when tools != [] and turn > 3, do: :complex
  defp assess_complexity(%{tools: tools}) when tools != [], do: :medium
  defp assess_complexity(_), do: :simple

  # -- tier selection --

  defp tier_for(:simple, _retries), do: :cheap
  defp tier_for(:medium, _retries), do: :mid
  defp tier_for(:complex, retries) when retries > 1, do: :best
  defp tier_for(:complex, _retries), do: :strong

  # -- model selection from provider config --

  defp select_model_by_tier(router, tier) when tier in @tiers do
    case models_for_tier(tier) do
      [] ->
        Logger.warning("SmartRouter: no enabled models found for tier #{tier}")
        {:error, {:all_unavailable, :infinity}}

      models ->
        # Try each model in this tier until we find an available provider
        try_models_in_tier(router, models, tier)
    end
  end

  defp select_model_by_tier(_router, tier), do: {:error, {:invalid_tier, tier}}

  defp try_models_in_tier(router, [model | rest], tier) do
    case Router.select(router, model: model.name) do
      {:ok, provider, model_name} ->
        {:ok, provider, model_name}

      {:error, _reason} ->
        try_models_in_tier(router, rest, tier)
    end
  end

  defp try_models_in_tier(_router, [], _tier) do
    {:error, {:all_unavailable, :infinity}}
  end

  defp models_for_tier(tier) do
    config = Application.get_env(:ai_brain, :smart_router, [])

    config
    |> configured_models(tier)
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn
      %{name: name} -> %{name: name}
      %{"name" => name} -> %{name: name}
      name when is_binary(name) -> %{name: name}
    end)
  end

  defp configured_models(config, tier) when is_list(config) do
    Keyword.get(config, tier) || Keyword.get(config, Atom.to_string(tier))
  end

  defp configured_models(config, tier) when is_map(config) do
    Map.get(config, tier) || Map.get(config, Atom.to_string(tier))
  end

  defp configured_models(_config, _tier), do: nil

  # -- fallback across tiers --

  defp try_fallback_tiers(_router, [], error), do: error

  defp try_fallback_tiers(router, [tier | rest], original_error) do
    case select_model_by_tier(router, tier) do
      {:ok, provider, model_name} ->
        Logger.info("SmartRouter: fell back to tier #{tier} with model #{model_name}")
        {:ok, provider, model_name}

      {:error, _} ->
        try_fallback_tiers(router, rest, original_error)
    end
  end
end
