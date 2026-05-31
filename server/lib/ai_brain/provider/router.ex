defmodule AIBrain.Provider.Router do
  use GenServer
  require Logger

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Select a provider for the given request.

  Three calling modes:
    1. Router.select(router, model: "gpt-4o") — direct model name
    2. Router.select(router, provider: :openai, type: :llm) — provider + type, use default
    3. Router.select(router, type: :llm) — type only, use highest-priority provider's default

  Returns {:ok, provider, model_name} or {:error, reason}.
  """
  def select(server \\ __MODULE__, opts) when is_list(opts) do
    GenServer.call(server, {:select, opts}, 10_000)
  end

  # Legacy API (deprecated)
  def select(server, protocol, model) do
    GenServer.call(server, {:select, protocol, model}, 10_000)
  end

  def set_cooldown(server \\ __MODULE__, provider_name, protocol, until) do
    GenServer.cast(server, {:set_cooldown, provider_name, protocol, until})
  end

  def normalize_protocol(protocol) when is_atom(protocol) do
    protocol |> Atom.to_string() |> normalize_protocol()
  end

  def normalize_protocol(protocol) when is_binary(protocol) do
    protocol
    |> String.downcase()
    |> case do
      "openai" -> "openai"
      "chat" -> "openai"
      "llm" -> "openai"
      other -> other
    end
  end

  def normalize_protocol(_), do: "openai"

  def all_providers(server \\ __MODULE__) do
    GenServer.call(server, :all_providers, 10_000)
  end

  def reload(server \\ __MODULE__, providers) do
    GenServer.call(server, {:reload, providers}, 10_000)
  end

  def reload_from_file(server \\ __MODULE__) do
    GenServer.call(server, :reload_from_file, 10_000)
  end

  # GenServer callbacks

  def init(opts) do
    providers =
      case Keyword.get(opts, :providers) do
        nil -> load_providers()
        list when is_list(list) -> list
      end

    {:ok, %{providers: providers, cooldowns: %{}}}
  end

  def handle_call({:select, opts}, _from, state) when is_list(opts) do
    # New API: keyword list
    mode = detect_select_mode(opts)

    reply =
      AIBrain.Telemetry.Metrics.span(
        [:router, :select],
        %{mode: mode, opts: opts},
        fn ->
          do_select(state, mode, opts)
        end
      )

    {:reply, reply, state}
  end

  def handle_call({:select, protocol, model}, _from, state) do
    # Legacy API: direct model selection
    reply =
      AIBrain.Telemetry.Metrics.span(
        [:router, :select],
        %{protocol: protocol, model: model, mode: :legacy},
        fn ->
          do_select(state, :model, model: model, protocol: protocol)
        end
      )

    {:reply, reply, state}
  end

  def handle_call(:all_providers, _from, state) do
    {:reply, state.providers, state}
  end

  def handle_call({:reload, providers}, _from, state) do
    {:reply, :ok, %{state | providers: providers}}
  end

  def handle_call(:reload_from_file, _from, state) do
    providers = load_providers()
    {:reply, :ok, %{state | providers: providers}}
  end

  def handle_cast(:reload_from_file, state) do
    providers = load_providers()
    {:noreply, %{state | providers: providers}}
  end

  def handle_cast({:set_cooldown, provider_name, protocol, until_ts}, state) do
    key = {provider_name, normalize_protocol(protocol)}
    {:noreply, put_in(state, [:cooldowns, key], until_ts)}
  end

  # ── Selection logic ───────────────────────────────────────────────

  defp do_select(%{providers: providers} = state, :model, opts) do
    model = Keyword.get(opts, :model)

    if is_nil(model) do
      {:error, :model_required}
    else
      # Handle ReqLLM "provider:model" format
      {target_provider, model_name} =
        case String.split(model, ":", parts: 2) do
          [p, m] -> {String.downcase(p), m}
          _ -> {nil, model}
        end

      # Find providers that have this model enabled.
      available_providers =
        Enum.filter(providers, fn p ->
          provider_available?(p, state) and has_model?(p, model_name) and
            (is_nil(target_provider) or String.downcase(p.name) == target_provider)
        end)

      case available_providers do
        [first | _] ->
          {:ok, first, model_name}

        [] ->
          # Fallback: try matching the raw model string (for custom provider models)
          fallback =
            Enum.filter(providers, fn p ->
              provider_available?(p, state) and has_model?(p, model)
            end)

          case fallback do
            [first | _] -> {:ok, first, model}
            [] -> {:error, {:no_provider_for_model, model}}
          end
      end
    end
  end

  defp do_select(%{providers: providers} = state, :provider_and_type, opts) do
    provider_name = Keyword.get(opts, :provider)
    type = Keyword.get(opts, :type)

    cond do
      is_nil(provider_name) ->
        {:error, :provider_required}

      is_nil(type) ->
        {:error, :type_required}

      true ->
        case Enum.find(providers, fn p ->
               p.name == provider_name and provider_available?(p, state)
             end) do
          nil ->
            {:error, {:provider_not_found, provider_name}}

          provider ->
            # Use the system default model if it matches this provider.
            # If settings storage is unavailable, fall back to the provider's
            # first enabled/manual/default model so background workers do not
            # crash on a DB read before they can report failure.
            case default_llm_model(providers, state) do
              {:ok, {^provider_name, model}} -> {:ok, provider, model}
              _ -> {:ok, provider, fallback_model(provider)}
            end
        end
    end
  end

  defp do_select(%{providers: providers} = state, :type_only, opts) do
    type = Keyword.get(opts, :type)

    if is_nil(type) do
      {:error, :type_required}
    else
      # Read default model from system settings (set via frontend), falling
      # back to priority order when settings are absent/unavailable.
      case default_llm_model(providers, state) do
        {:ok, {provider_name, model_name}} ->
          case Enum.find(providers, fn p ->
                 p.name == provider_name and provider_available?(p, state)
               end) do
            nil ->
              case first_enabled_provider(providers, state) do
                nil -> {:error, {:provider_not_found, provider_name}}
                provider -> {:ok, provider, fallback_model(provider)}
              end

            provider ->
              {:ok, provider, model_name}
          end

        {:error, _} ->
          case first_enabled_provider(providers, state) do
            nil -> unavailable_error(providers, state, {:no_default_model_for_type, type})
            provider -> {:ok, provider, fallback_model(provider)}
          end
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp detect_select_mode(opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :model) -> :model
      Keyword.has_key?(opts, :provider) and Keyword.has_key?(opts, :type) -> :provider_and_type
      Keyword.has_key?(opts, :type) -> :type_only
      true -> :invalid
    end
  end

  defp has_model?(provider, model_name) do
    cond do
      model_name == "default" ->
        true

      AIBrain.Provider.Info.has_model?(provider, model_name) ->
        true

      String.downcase(provider.name) == "openrouter" ->
        case AIBrain.Config.FileBackend.load_global_models() do
          {:ok, models} when models != [] ->
            Enum.any?(models, fn m -> m["id"] == model_name or m["name"] == model_name end)

          _ ->
            false
        end

      true ->
        cached_model?(provider, model_name)
    end
  end

  defp cached_model?(provider, model_name) do
    case AIBrain.Config.FileBackend.load_cached_models(provider.name) do
      {:ok, models} ->
        Enum.any?(models, fn m -> m["name"] == model_name or m["id"] == model_name end)

      {:error, _} ->
        false
    end
  end

  defp provider_enabled?(provider), do: Map.get(provider, :enabled) != false

  defp provider_available?(provider, state) do
    provider_enabled?(provider) and not cooldown_active?(provider, "openai", state)
  end

  defp cooldown_active?(provider, protocol, %{cooldowns: cooldowns}) do
    case Map.get(cooldowns, {provider.name, normalize_protocol(protocol)}) do
      nil -> false
      until_ts -> until_ts > System.os_time(:millisecond) / 1000
    end
  end

  defp first_enabled_provider(providers, state) do
    providers
    |> Enum.filter(&provider_available?(&1, state))
    |> Enum.sort_by(&(&1.priority || 100))
    |> List.first()
  end

  defp unavailable_error(providers, state, fallback) do
    soonest =
      providers
      |> Enum.map(&Map.get(state.cooldowns, {&1.name, "openai"}))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(&1 > System.os_time(:millisecond) / 1000))
      |> Enum.min(fn -> nil end)

    if soonest, do: {:error, {:all_unavailable, soonest}}, else: {:error, fallback}
  end

  defp fallback_model(provider) do
    enabled = AIBrain.Provider.Info.enabled_models(provider)

    if enabled != [] do
      Enum.find(enabled, &has_llm_model?(provider, &1)) || List.first(enabled)
    else
      "default"
    end
  end

  defp default_llm_model(providers, state) do
    [
      AIBrain.Data.SystemSetting.default_llm_model(),
      AIBrain.Data.SystemSetting.default_model("normal"),
      AIBrain.Data.SystemSetting.default_model("lite")
    ]
    |> Enum.uniq()
    |> Enum.find_value(fn
      {provider_name, model_name} when is_binary(provider_name) and is_binary(model_name) ->
        case Enum.find(providers, fn provider ->
               provider.name == provider_name and provider_available?(provider, state) and
                 has_llm_model?(provider, model_name)
             end) do
          nil -> nil
          _provider -> {:ok, {provider_name, model_name}}
        end

      _ ->
        nil
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp has_llm_model?(provider, model_name) do
    has_model?(provider, model_name) and
      model_type(provider, model_name) not in ["image", "video", "audio"]
  end

  defp model_type(provider, model_name) do
    case AIBrain.Provider.Info.model_meta(provider, model_name) do
      %{"type" => type} when is_binary(type) and type != "" ->
        case type do
          "text" -> "llm"
          other -> other
        end

      %{"types" => types} when is_list(types) ->
        cond do
          Enum.any?(types, &(&1 in ["image", "video", "audio"])) ->
            Enum.find(types, &(&1 in ["image", "video", "audio"]))

          true ->
            "llm"
        end

      _ ->
        "llm"
    end
  end

  defp load_providers do
    try do
      AIBrain.Provider.Registry.all_providers()
    rescue
      e ->
        Logger.error("AIBrain.Provider.Router.load_providers failed: #{Exception.message(e)}")
        []
    end
  end
end
