defmodule AIBrain.Interaction.Manager do
  @moduledoc """
  Manages the full lifecycle of user-facing interactions.

  ## Flow

       request(type, schema, context, resume_token)
            │
            ▼
       create interaction (DB) — status: pending
            │
            ▼
       cast :interaction_needed (Bus) — any subscriber picks it up
            │
            ▼
       Proxy claims (pending → proxy_running)
            │
            ├── resolves → DB: resolved → cast :interaction_resolved
            │                → Resumer resumes (if resume_token)
            │
            └── escalates → DB: need_manual → cast :interaction_escalated
                             → user handles via API → Manager.resolve
  """

  use GenServer
  require Logger

  alias AIBrain.Data.{Goals, Interactions}
  alias AIBrain.Channel.Bus
  alias AIBrain.Core.Events

  @default_expiry_seconds 300
  @sweep_interval_ms 300_000

  # ── Client API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Submit an interaction request. Creates the record, emits the event.
  Returns `{:ok, interaction_id}` or `{:error, reason}`.
  """
  def request(type, schema, context, opts \\ []) do
    GenServer.call(__MODULE__, {:request, type, schema, context, opts}, 15_000)
  end

  @doc "Resolve an interaction by ID. Called by users via API."
  def resolve(interaction_id, result, resolved_by \\ AIBrain.Data.Users.default_user_id()) do
    resolve(interaction_id, result, resolved_by, [])
  end

  def resolve(interaction_id, result, resolved_by, opts) do
    GenServer.call(__MODULE__, {:resolve, interaction_id, result, resolved_by, opts}, 10_000)
  end

  @doc "Mark partial proxy trail on a pending interaction."
  def append_trail(interaction_id, trail_entry) do
    GenServer.cast(__MODULE__, {:append_trail, interaction_id, trail_entry})
  end

  @doc "Get interaction chain for a session (no GenServer call — reads DB directly)."
  def session_chain(session_id) do
    Interactions.chain_for_session(session_id)
  end

  # ── Callbacks ──

  @impl true
  def init(_opts) do
    Logger.info("InteractionManager started")
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:request, type, schema, context, opts}, _from, state) do
    resume_token = Keyword.get(opts, :resume_token)
    expires_in = Keyword.get(opts, :expires_in, @default_expiry_seconds)
    prompt_versions = Keyword.get(opts, :prompt_versions, %{})

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(expires_in, :second)
      |> DateTime.to_iso8601()

    attrs = %{
      type: to_string(type),
      status: "pending",
      schema_data: schema,
      context: context,
      resume_token: resume_token,
      prompt_versions: prompt_versions,
      expires_at: expires_at
    }

    case Interactions.create(attrs) do
      {:ok, interaction} ->
        Bus.publish(
          Events.interaction_needed(
            interaction.id,
            type,
            schema,
            context,
            expires_at: expires_at
          )
        )

        Logger.info("InteractionManager: created #{type} interaction #{interaction.id}")
        {:reply, {:ok, interaction.id}, state}

      {:error, changeset} ->
        {:reply, {:error, inspect(changeset.errors)}, state}
    end
  end

  @impl true
  def handle_call({:resolve, interaction_id, result, resolved_by, opts}, _from, state) do
    proxy_trail = Keyword.get(opts, :proxy_trail)

    case Interactions.resolve(interaction_id, result, resolved_by, proxy_trail: proxy_trail) do
      {:ok, interaction} ->
        apply_domain_resolution(interaction, result, resolved_by)

        Bus.publish(
          Events.interaction_resolved(interaction_id, result, resolved_by, %{
            resume_token: interaction.resume_token,
            proxy_trail: interaction.proxy_trail || []
          })
        )

        Logger.info("InteractionManager: resolved #{interaction_id} by #{resolved_by}")

        # Run resume continues in AuthorizationWorkflow (blocks on Bus until resolved).

        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:append_trail, interaction_id, trail_entry}, state) do
    interaction = Interactions.get(interaction_id)

    case interaction do
      nil ->
        {:noreply, state}

      i ->
        current_trail = i.proxy_trail || []
        updated = current_trail ++ [trail_entry]
        Ecto.Changeset.change(i, proxy_trail: updated) |> AIBrain.Repo.update()
        {:noreply, state}
    end
  rescue
    _ -> {:noreply, state}
  end

  @impl true
  def handle_info(:sweep_expired, state) do
    expired = Interactions.expired()

    if expired != [] do
      count =
        Enum.count(expired, fn i ->
          case Interactions.expire(i.id) do
            {:ok, interaction} ->
              handle_expired_interaction(interaction)
              true

            _ ->
              false
          end
        end)

      Logger.info("InteractionManager: swept #{count}/#{length(expired)} expired interactions")
    end

    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────

  defp schedule_sweep do
    Process.send_after(self(), :sweep_expired, @sweep_interval_ms)
  end

  defp handle_expired_interaction(interaction) do
    context = interaction.context || %{}

    Bus.publish(
      Events.interaction_expired(interaction.id, interaction.type, %{
        resume_token: interaction.resume_token,
        run_id: context["run_id"] || context[:run_id],
        session_id: context["session_id"] || context[:session_id]
      })
    )
  end

  defp apply_domain_resolution(
         %{context: %{"kind" => "goal_owner_input"} = context},
         result,
         resolved_by
       ) do
    goal_id = context["goal_id"]

    with goal_id when is_binary(goal_id) and goal_id != "" <- goal_id,
         {:ok, goal} <- Goals.get(goal_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      payload = normalize_result_payload(result)
      decision = normalize_decision(map_get(payload, "decision"))
      response = owner_response(payload)

      metadata =
        goal.metadata
        |> normalize_metadata()
        |> update_strategy_after_owner_response(decision, response, now)
        |> Map.put("last_owner_interaction_resolved_at", now)
        |> Map.put("last_owner_interaction_resolved_by", to_string(resolved_by))
        |> Map.put("last_owner_interaction_decision", decision)
        |> maybe_put("last_owner_interaction_response", response)
        |> maybe_schedule_followup(decision, now)

      attrs =
        case decision do
          "pause_goal" -> %{status: "paused", metadata: metadata}
          _ -> %{status: "active", metadata: metadata}
        end

      case Goals.update(goal.id, attrs) do
        {:ok, _goal} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "InteractionManager: failed to apply goal interaction: #{inspect(reason)}"
          )
      end
    end
  rescue
    e ->
      Logger.warning(
        "InteractionManager: goal interaction resolution failed: #{Exception.message(e)}"
      )

      :ok
  end

  defp apply_domain_resolution(_interaction, _result, _resolved_by), do: :ok

  defp normalize_result_payload(%{form: form}) when is_map(form), do: normalize_metadata(form)
  defp normalize_result_payload(%{"form" => form}) when is_map(form), do: normalize_metadata(form)
  defp normalize_result_payload(result) when is_map(result), do: normalize_metadata(result)
  defp normalize_result_payload(_), do: %{}

  defp normalize_decision("pause_goal"), do: "pause_goal"
  defp normalize_decision("revise_strategy"), do: "revise_strategy"
  defp normalize_decision("continue"), do: "continue"
  defp normalize_decision(:pause_goal), do: "pause_goal"
  defp normalize_decision(:revise_strategy), do: "revise_strategy"
  defp normalize_decision(:continue), do: "continue"
  defp normalize_decision(_), do: "continue"

  defp update_strategy_after_owner_response(metadata, decision, response, now) do
    strategy =
      metadata
      |> Map.get("strategy", %{})
      |> normalize_metadata()
      |> Map.put("needs_owner_input", decision == "revise_strategy")
      |> Map.put("owner_decision", decision)
      |> Map.put("owner_resolved_at", now)
      |> maybe_put("owner_response", response)

    Map.put(metadata, "strategy", strategy)
  end

  defp owner_response(result) when is_map(result) do
    result
    |> map_get("response", map_get(result, "text", ""))
    |> to_string()
    |> String.trim()
    |> truncate_text(2_000)
  end

  defp owner_response(_), do: ""

  defp maybe_schedule_followup(metadata, "pause_goal", _now),
    do: Map.delete(metadata, "next_review_after")

  defp maybe_schedule_followup(metadata, _decision, now),
    do: Map.put(metadata, "next_review_after", now)

  defp normalize_metadata(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), val} end)
  end

  defp normalize_metadata(_), do: %{}

  defp map_get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, existing_atom_key(key), default))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp existing_atom_key(key), do: key

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truncate_text(text, limit) when byte_size(text) <= limit, do: text
  defp truncate_text(text, limit), do: String.slice(text, 0, limit)
end
