defmodule AIBrain.AgentRuntime.AuthorizationWorkflow do
  @moduledoc """
  Tool authorization logic — permission checks, approval suspension, interaction creation.
  """

  require Logger

  def authorize_tool(run_id, request, opts) do
    registry = Keyword.get(opts, :registry, AIBrain.Tool.Registry)
    mode = permission_mode(request, opts)
    resolver = Keyword.get(opts, :approval_resolver)
    on_event = Keyword.get(opts, :on_event, fn _ -> :ok end)
    autonomy_level = autonomy_level(request, opts)
    autonomy_allowed_tools = Keyword.get(opts, :autonomy_allowed_tools, [])

    fn tool_use ->
      tool_name = tool_name(tool_use)
      risk = AIBrain.Tool.Registry.risk_category(registry, tool_name)
      effective_mode =
        effective_permission_mode(mode, tool_name, autonomy_allowed_tools, registry, autonomy_level)

      if AIBrain.Permissions.Modes.normalize(effective_mode) == :approval_required and
           is_nil(resolver) and risk != :read_only do
        emit_permission_checked(on_event, tool_use, :suspended, risk, :approval_required)
        wait_for_approval(run_id, request, tool_use, risk, opts)
      else
        case AIBrain.Permissions.Policy.authorize(tool_use, registry,
               mode: effective_mode,
               approval_resolver: resolver
             ) do
          {:allow, authorized_tool_use, meta} ->
            emit_permission_checked(on_event, tool_use, :allowed, risk, meta[:reason])
            {:allow, authorized_tool_use}

          {:deny, reason, meta} ->
            emit_permission_checked(on_event, tool_use, :denied, risk, meta[:reason] || reason)
            {:deny, reason}
        end
      end
    end
  end

  defp wait_for_approval(run_id, request, tool_use, risk, _opts) do
    resume_token = AIBrain.Session.ShortID.session_id()

    pending_tool = %{
      "id" => tool_id(tool_use),
      "name" => tool_name(tool_use),
      "input" => tool_input(tool_use)
    }

    context = %{
      "run_id" => run_id,
      "session_id" => request.session_id,
      "tool_use" => pending_tool,
      "risk" => Atom.to_string(risk),
      "system_prompt" => nil
    }

    case AIBrain.Interaction.Manager.request(
           :approval,
           %{
             "title" => "Approve tool: #{tool_name(tool_use)}",
             "tool_name" => tool_name(tool_use),
             "tool_input" => tool_input(tool_use),
             "risk" => Atom.to_string(risk)
           },
           context,
           resume_token: resume_token
         ) do
      {:ok, interaction_id} ->
        Logger.info(
          "AuthorizationWorkflow: waiting for approval #{interaction_id} (run #{run_id})"
        )

        # Block until interaction is resolved or expired.
        # Run stays "running" — the engine loop just waits for a human decision.
        decision = await_interaction_resolution(interaction_id)

        case decision do
          :approved -> :allow
          {:denied, reason} -> {:deny, reason}
        end

      _ ->
        Logger.warning("AuthorizationWorkflow: failed to create interaction for run #{run_id}")
        {:deny, "approval_system_unavailable"}
    end
  end

  defp await_interaction_resolution(interaction_id) do
    # Subscribe to Bus events for this specific interaction
    try do
      AIBrain.Channel.Bus.subscribe(self())
    rescue
      _ -> :ok
    end

    await_loop(interaction_id)
  end

  defp await_loop(interaction_id) do
    receive do
      {:bus_event, %{type: :interaction_resolved, interaction_id: ^interaction_id} = event} ->
        result = event[:result] || event["result"] || %{}
        decision = result[:decision] || result["decision"]

        case decision do
          :denied -> {:denied, "User denied the request"}
          "denied" -> {:denied, "User denied the request"}
          :approved -> :approved
          "approved" -> :approved
          _ -> :approved
        end

      {:bus_event, %{type: :interaction_expired, interaction_id: ^interaction_id}} ->
        {:denied, "Approval request expired"}

      {:DOWN, _ref, :process, _pid, _reason} ->
        {:denied, "Caller process terminated"}

      {:EXIT, _pid, _reason} ->
        {:denied, "Caller process exited"}

      _other ->
        # Ignore unrecognized messages — don't re-queue.
        # Re-queuing with Process.send/3 can cause infinite loops
        # when system messages (DOWN, EXIT) arrive during the wait.
        await_loop(interaction_id)
    after
      300_000 ->
        {:denied, "Approval request timed out"}
    end
  end

  def permission_mode(_request, opts) do
    case Keyword.get(opts, :permission_mode) do
      nil ->
        # Legacy: HTTP/SSE passed mode as string; WS must set permission_mode explicitly.
        opts
        |> Keyword.get(:mode, :approval_required)
        |> AIBrain.Permissions.Modes.normalize()

      mode ->
        AIBrain.Permissions.Modes.normalize(mode)
    end
  end

  defp effective_permission_mode(mode, tool_name, allowed_tools, registry, autonomy_level) do
    normalized = AIBrain.Permissions.Modes.normalize(mode)

    cond do
      normalized == :approval_required and tool_name in allowed_tools ->
        :execute

      normalized == :approval_required and
          AIBrain.Permissions.Autonomy.auto_allowed?(autonomy_level, tool_name, registry) ->
        :execute

      true ->
        normalized
    end
  end

  defp autonomy_level(request, opts) do
    level = Keyword.get(opts, :autonomy_level, request.autonomy_level || 0)

    case level do
      n when is_integer(n) -> n
      n when is_binary(n) ->
        case Integer.parse(n) do
          {int, _} -> int
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp emit_permission_checked(on_event, tool_use, decision, risk, reason) do
    on_event.(%{
      type: :permission_checked,
      tool_name: tool_name(tool_use),
      tool_use_id: tool_id(tool_use),
      decision: decision,
      risk: risk,
      reason: reason
    })
  rescue
    _ -> :ok
  end

  def tool_id(%{id: id}), do: id
  def tool_id(%{"id" => id}), do: id
  def tool_id(_), do: nil

  def tool_name(%{name: name}), do: name
  def tool_name(%{"name" => name}), do: name
  def tool_name(_), do: nil

  def tool_input(%{input: input}), do: input
  def tool_input(%{"input" => input}), do: input
  def tool_input(_), do: %{}
end
