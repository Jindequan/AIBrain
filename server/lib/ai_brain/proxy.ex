defmodule AIBrain.Proxy do
  @moduledoc """
  User's decision proxy — acts in the user's stead.
  Subscribes to Bus events, evaluates via LLM, and acts autonomously.

  Events handled:
    run_completed_for_review  → decide post-run action
    approval_pending_review   → decide approve/deny/escalate
    interaction_needed        → decide based on type (confirm/select/text_input)
  """

  use GenServer
  require Logger

  # ── Client API ──────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Notify the proxy GenServer that its active state changed. Called by ProxyControl tool."
  def set_active(active?) do
    GenServer.cast(__MODULE__, {:set_active, active?})
  end

  @doc "Set autonomy mode. In autonomy mode, the proxy never escalates — it must decide."
  def set_autonomy(enabled?) do
    GenServer.cast(__MODULE__, {:set_autonomy, enabled?})
  end

  # ── Callbacks ───────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    # Always subscribe — even when inactive, we claim interactions and escalate
    AIBrain.Channel.Bus.subscribe(self())
    active = proxy_active?()
    autonomy = proxy_autonomy?()

    Logger.info("Proxy started — #{if active, do: "active", else: "inactive"}, #{if autonomy, do: "autonomy", else: "assist"}")

    {:ok, %{active: active, autonomy: autonomy, pending_tasks: %{}}}
  end

  @impl true
  def handle_info({:bus_event, %{type: :run_completed_for_review} = event}, state) do
    spawn_run_review(event)
    {:noreply, state}
  end

  def handle_info({:bus_event, %{type: :interaction_needed} = event}, state) do
    handle_interaction_needed(event, state)
    {:noreply, state}
  end

  def handle_info({:bus_event, _}, state), do: {:noreply, state}

  # Track async task pid → context
  def handle_info({:proxy_track_task, pid, kind_ctx}, state) do
    {:noreply, put_in(state, [:pending_tasks, pid], kind_ctx)}
  end

  # Async LLM task completed — dispatch result
  def handle_info({:proxy_llm_result, pid, {kind_ctx, result}}, state) do
    handle_llm_result(kind_ctx, result)

    {:noreply, update_in(state.pending_tasks, &Map.delete(&1, pid))}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    if Map.has_key?(state.pending_tasks, pid) do
      kind_ctx = state.pending_tasks[pid]
      Logger.warning("Proxy: async LLM task exited: #{inspect(reason)}")

      # If this was an interaction evaluation, escalate to human on crash
      case kind_ctx do
        {:interaction, interaction_id, _type, _versions, _autonomy?} ->
          escalate_to_human(interaction_id, "proxy_llm_crashed")
        _ ->
          :ok
      end

      {:noreply, update_in(state.pending_tasks, &Map.delete(&1, pid))}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:set_active, active?}, state) do
    {:noreply, %{state | active: active?}}
  end

  def handle_cast({:set_autonomy, enabled?}, state) do
    {:noreply, %{state | autonomy: enabled?}}
  end

  # ── Async LLM dispatch ──────────────────────────────────────

  defp spawn_run_review(event) do
    ctx = AIBrain.Data.Runs.load_context(event[:run_id])
    prompt = run_review_prompt(ctx)
    spawn_llm_task({:run_review, ctx}, prompt)
  rescue
    e -> Logger.warning("Proxy: run review dispatch failed: #{Exception.message(e)}")
  end

  defp spawn_interaction_llm(event, interaction_id, lesson_versions, autonomy?) do
    interaction_type = event[:interaction_type]
    schema = event[:schema] || %{}
    context = event[:context] || %{}
    lessons_text = AIBrain.Feedback.lessons_for_prompt(:proxy)
    prompt = interaction_prompt(interaction_type, schema, context, lessons_text, autonomy?)

    spawn_llm_task(
      {:interaction, interaction_id, interaction_type, lesson_versions, autonomy?},
      prompt
    )
  end

  defp spawn_llm_task(kind_ctx, prompt) do
    parent = self()

    {:ok, pid} =
      Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
        result = call_llm(prompt)
        task_pid = self()
        send(parent, {:proxy_llm_result, task_pid, {kind_ctx, result}})
      end)

    # Track pid → {kind, context} for result dispatch
    send(parent, {:proxy_track_task, pid, kind_ctx})
  end

  # ── LLM result handlers ────────────────────────────────────

  defp handle_llm_result({:run_review, ctx}, result) do
    case result do
      {:ok, text} ->
        case extract_action(text) do
          "send_message" -> send_proxy_message(ctx, text)
          "continue" -> create_next_task(ctx, text)
          "retry" -> retry_task(ctx)
          "complete" -> complete_goal(ctx)
          "escalate" -> escalate(ctx, text)
          _ -> :ok
        end

      {:error, reason} ->
        Logger.warning("Proxy: run review LLM failed: #{inspect(reason)}")
    end
  rescue
    e -> Logger.warning("Proxy: run review handler failed: #{Exception.message(e)}")
  end

  defp handle_llm_result({:interaction, interaction_id, type, lesson_versions, autonomy?}, result) do
    case result do
      {:ok, text} ->
        interaction = AIBrain.Data.Interactions.get(interaction_id)

        if interaction && interaction.status == "proxy_running" do
          handle_interaction_result(interaction_id, type, text, lesson_versions, autonomy?)
        else
          Logger.info(
            "Proxy: interaction #{interaction_id} status changed to #{interaction && interaction.status}, discarding result"
          )
        end

      {:error, _reason} ->
        if autonomy? do
          Logger.info("Proxy: autonomy — LLM call failed, approving to keep moving")
          resolve_interaction(interaction_id, "approved", [])
        else
          escalate_to_human(interaction_id, "Proxy LLM call failed")
        end
    end
  rescue
    e -> Logger.warning("Proxy: interaction handler failed: #{Exception.message(e)}")
  end

  defp handle_llm_result({:interaction, interaction_id, type, lesson_versions}, result) do
    handle_llm_result({:interaction, interaction_id, type, lesson_versions, false}, result)
  end

  # ── Approval Review ─────────────────────────────────────────

  # ── Actions ─────────────────────────────────────────────────

  defp send_proxy_message(_ctx, text) do
    msg = extract_field(text, "message") || default_proxy_message()
    store = AIBrain.Config.session_store()
    sessions = store.list_sessions(store, limit: 1)

    if sessions != [] do
      sid = hd(sessions).id
      store.append_message(store, sid, %{role: "assistant", content: msg})
      Logger.info("Proxy: sent message to session #{sid}")
    end
  rescue
    e -> Logger.warning("Proxy: send_message failed: #{Exception.message(e)}")
  end

  defp default_proxy_message do
    lang = AIBrain.User.preferences()["language"] || "zh"

    case lang do
      "en" -> "This looks good. What's the next step?"
      _ -> "看起来不错。下一步是什么？"
    end
  rescue
    _ -> "看起来不错。下一步是什么？"
  end

  defp create_next_task(ctx, text) do
    title = extract_field(text, "next_task_title") || "Continue"

    case AIBrain.Data.Tasks.create_task(%{
           goal_id: ctx[:goal_id],
           title: title,
           description: "",
           status: "pending"
         }) do
      {:ok, task} ->
        AIBrain.Task.Dispatcher.notify_pending(task.id)
        {:ok, task}

      error ->
        error
    end
  rescue
    e -> Logger.warning("Proxy: create_task failed: #{Exception.message(e)}")
  end

  defp retry_task(_ctx) do
    # Dispatcher will pick up the task on next poll
    :ok
  rescue
    e -> Logger.warning("Proxy: retry failed: #{Exception.message(e)}")
  end

  defp complete_goal(ctx) do
    AIBrain.Data.Goals.update(ctx[:goal_id], %{status: "completed"})
  rescue
    e -> Logger.warning("Proxy: complete failed: #{Exception.message(e)}")
  end

  defp escalate(ctx, text) do
    reason = extract_field(text, "reason") || "Needs your attention"

    AIBrain.Channel.Bus.publish(%{
      type: :proxy_escalated,
      reason: reason,
      goal_id: ctx[:goal_id],
      run_id: ctx[:run_id]
    })
  rescue
    e -> Logger.warning("Proxy: escalate failed: #{Exception.message(e)}")
  end

  # ── Interaction Review ───────────────────────────────────────

  defp handle_interaction_needed(event, state) do
    interaction_id = event[:interaction_id]

    # CAS: claim this interaction for proxy processing
    case AIBrain.Data.Interactions.claim_for_proxy(interaction_id) do
      {:ok, _interaction} ->
        # We own it — decide how to handle
        do_process_interaction(event, state.active)

      {:error, :wrong_status} ->
        # Someone else already claimed or it's been handled — skip
        :ok

      {:error, :not_found} ->
        Logger.warning("Proxy: interaction #{interaction_id} not found")
        :ok
    end
  rescue
    e -> Logger.warning("Proxy: interaction review failed: #{Exception.message(e)}")
  end

  defp do_process_interaction(event, state) do
    interaction_id = event[:interaction_id]
    interaction_type = event[:interaction_type]
    active? = state.active
    autonomy? = state.autonomy

    original_reason =
      case AIBrain.Data.Interactions.get(interaction_id) do
        %{schema_data: %{"reason" => r}} when is_binary(r) -> r
        _ -> nil
      end

    cond do
      # Autonomy mode: proxy MUST decide. No human available. Handle all types.
      autonomy? and active? ->
        process_interaction_llm(event, interaction_id, autonomy: true)

      # Sandbox operations — proxy cannot authorize these in assist mode.
      interaction_type in ~w(shell_exec)a ->
        escalate_to_human(interaction_id, original_reason || "human_only_sandbox")

      # Proxy inactive — escalate all decisions to human.
      not active? ->
        escalate_to_human(interaction_id, original_reason || "proxy_inactive")

      # Active assist mode — LLM evaluates and may escalate.
      true ->
        process_interaction_llm(event, interaction_id, autonomy: false)
    end
  end

  defp escalate_to_human(interaction_id, reason) do
    AIBrain.Data.Interactions.mark_need_manual(interaction_id, reason: reason)
    publish_interaction_escalated(interaction_id, reason, [])
    :ok
  end

  defp process_interaction_llm(event, interaction_id, opts) do
    lessons = AIBrain.Feedback.active_lessons(:proxy)
    lesson_versions = Map.new(lessons, fn l -> {l.id, l.version} end)
    autonomy? = Keyword.get(opts, :autonomy, false)

    spawn_interaction_llm(event, interaction_id, lesson_versions, autonomy?)
  rescue
    e ->
      Logger.warning("Proxy: interaction LLM dispatch failed: #{Exception.message(e)}")

      if Keyword.get(opts, :autonomy, false) do
        # Autonomy mode: can't escalate to human. Approve by default — keep the project moving.
        Logger.info("Proxy: autonomy mode — approving on LLM failure for #{interaction_id}")
        resolve_interaction(interaction_id, "approved", [])
      else
        original_reason =
          case AIBrain.Data.Interactions.get(interaction_id) do
            %{schema_data: %{"reason" => r}} when is_binary(r) -> r
            _ -> nil
          end

        escalate_to_human(interaction_id, original_reason || "llm_dispatch_failed")
      end
  end

  defp interaction_prompt(:confirm, schema, context, lessons_text, autonomy?) do
    autonomy_note = if autonomy?, do: autonomy_instructions(), else: ""

    """
    #{AIBrain.Prompts.proxy_identity()}
    #{user_context_block()}
    #{autonomy_note}

    ## Confirmation Request
    Title: #{schema[:title] || "Confirmation"}
    Prompt: #{schema[:prompt] || "Please confirm this action."}

    ## Context
    Source: #{context[:source] || "unknown"}
    Session: #{context[:session_id] || "unknown"}
    #{if lessons_text != "", do: lessons_text}

    ## Available Actions
    - approve → "reason": "why this is safe and aligned"
    - deny → "reason": "why this is unnecessary or dangerous"
    #{unless autonomy?, do: "- escalate → \"reason\": \"why you cannot decide\""}

    #{if autonomy?, do: "The user is UNAVAILABLE. You MUST decide. Do not escalate.", else: "Before deciding: VERIFY your assessment against the user's goals and risk tolerance. If you cannot verify safety and alignment, escalate."}

    Reply with ONLY JSON: {"action":"...", "reason":"..."}
    """
  end

  defp interaction_prompt(:select, schema, context, lessons_text, autonomy?) do
    options =
      schema[:fields]
      |> List.wrap()
      |> Enum.find(%{}, fn f -> is_map(f) && f[:key] == :choice end)
      |> Map.get(:options, [])

    options_text =
      if options != [] do
        Enum.with_index(options, 1)
        |> Enum.map(fn {opt, i} -> "  #{i}. #{inspect(opt)}" end)
        |> Enum.join("\n")
      else
        "  (no options provided)"
      end

    autonomy_note = if autonomy?, do: autonomy_instructions(), else: ""

    """
    #{AIBrain.Prompts.proxy_identity()}
    #{user_context_block()}
    #{autonomy_note}

    ## Selection Request
    Title: #{schema[:title] || "Selection"}
    Prompt: #{schema[:prompt] || "Please choose an option."}

    ## Options
    #{options_text}

    ## Context
    Source: #{context[:source] || "unknown"}
    Session: #{context[:session_id] || "unknown"}
    #{if lessons_text != "", do: lessons_text}

    ## Available Actions
    - select → "option_index": <number>, "reason": "why this choice"
    #{unless autonomy?, do: "- escalate → \"reason\": \"why you cannot decide\""}

    #{if autonomy?, do: "The user is UNAVAILABLE. You MUST pick an option.", else: "Before deciding: VERIFY which option best aligns with the user's goals. If you cannot determine the right choice, escalate."}

    Reply with ONLY JSON: {"action":"...", "option_index":<number>, "reason":"..."}
    """
  end

  defp interaction_prompt(:text_input, schema, context, lessons_text, _autonomy?) do
    """
    #{AIBrain.Prompts.proxy_identity()}
    #{user_context_block()}

    ## Information Request
    Title: #{schema[:title] || "Information Required"}
    Prompt: #{schema[:prompt] || "Please provide information."}

    ## Context
    Source: #{context[:source] || "unknown"}
    Session: #{context[:session_id] || "unknown"}
    #{if lessons_text != "", do: lessons_text}

    ## Available Actions
    - answer → "response": "your answer", "reason": "why this answer is appropriate"
    - escalate → "reason": "why you cannot answer"

    Before deciding: Can you provide the requested information based on what you know?
    If the request is ambiguous, requires user-specific knowledge, or involves sensitive data, escalate.

    Reply with ONLY JSON: {"action":"...", "response":"...", "reason":"..."}
    """
  end

  defp interaction_prompt(:form, schema, context, lessons_text, _autonomy?) do
    fields = List.wrap(schema[:fields])
    title = schema[:title] || "Form"
    prompt = schema[:prompt] || "Please fill out the following fields."

    fields_text =
      fields
      |> Enum.with_index(1)
      |> Enum.map(fn {f, i} ->
        label = f[:label] || f[:key] || "Field #{i}"
        type = f[:type] || "text"
        required = if f[:required], do: "(required)", else: "(optional)"

        opts =
          f[:options]
          |> List.wrap()
          |> Enum.with_index(1)
          |> Enum.map(fn {o, j} -> "    #{j}. #{o}" end)

        options_text = if opts != [], do: "\n    Options:\n#{Enum.join(opts, "\n")}", else: ""
        "  #{i}. [#{type}] #{label} #{required}#{options_text}"
      end)
      |> Enum.join("\n")

    """
    #{AIBrain.Prompts.proxy_identity()}
    #{user_context_block()}

    ## Form Request
    Title: #{title}
    Prompt: #{prompt}

    ## Fields to Fill
    #{fields_text}

    ## Context
    Source: #{context[:source] || "unknown"}
    Session: #{context[:session_id] || "unknown"}
    #{if lessons_text != "", do: lessons_text}

    ## Available Actions
    - submit → "values": {"field_key": "value", ...}, "reason": "why these values are appropriate"
    - escalate → "reason": "why you cannot fill this form"

    Before deciding: Can you provide ALL required fields based on what you know?
    If any required field is ambiguous, requires user-specific knowledge, or involves sensitive data, escalate.

    Reply with ONLY JSON: {"action":"...", "values":{...}, "reason":"..."}
    """
  end

  defp interaction_prompt(type, _schema, _context, _lessons_text, _autonomy?) do
    """
    #{AIBrain.Prompts.proxy_identity()}
    #{user_context_block()}

    ## Unknown Interaction Type: #{inspect(type)}

    Reply with ONLY JSON: {"action":"deny", "reason":"unsupported interaction type"}
    """
  end

  defp autonomy_instructions do
    """
    ## AUTONOMY MODE — USER IS UNAVAILABLE

    The user has enabled full autonomy. You MUST make a decision.
    Escalation is NOT possible — there is no human to escalate to.

    - Approve when aligned with project goals and reasonably safe.
    - Deny when the action would cause irreversible damage.
    - When uncertain, lean toward APPROVE to keep the project moving.
    """
  end

  defp handle_interaction_result(interaction_id, _interaction_type, text, lesson_versions, autonomy?) do
    action = extract_field(text, "action")
    reasoning = extract_field(text, "reason") || ""
    trail_entry = %{step: "assessment", action: action, reasoning: reasoning}

    trail_entry =
      if lesson_versions != %{},
        do: Map.put(trail_entry, :prompt_versions, lesson_versions),
        else: trail_entry

    proxy_trail = [trail_entry]

    case action do
      "approve" ->
        result = %{decision: :approved}
        resolve_interaction(interaction_id, result, proxy_trail)

      "deny" ->
        result = %{decision: :denied, reason: reasoning}
        resolve_interaction(interaction_id, result, proxy_trail)

      "select" ->
        option_idx = extract_field(text, "option_index")
        result = %{selected_index: option_idx}
        resolve_interaction(interaction_id, result, proxy_trail)

      "answer" ->
        response = extract_field(text, "response") || ""
        result = %{text: response}
        resolve_interaction(interaction_id, result, proxy_trail)

      "submit" ->
        values = extract_field(text, "values") || %{}
        result = %{form: values}
        resolve_interaction(interaction_id, result, proxy_trail)

      "escalate" ->
        if autonomy? do
          # Autonomy mode: no human to escalate to. Deny instead.
          Logger.info("Proxy: autonomy — escalate not allowed, denying instead for #{interaction_id}")
          result = %{decision: :denied, reason: "autonomy_no_escalate: #{reasoning}"}
          resolve_interaction(interaction_id, result, proxy_trail)
        else
          AIBrain.Data.Interactions.mark_need_manual(interaction_id,
            proxy_trail: proxy_trail,
            reason: reasoning
          )

          publish_interaction_escalated(interaction_id, reasoning, proxy_trail)
        end

      _ ->
        if autonomy? do
          Logger.info("Proxy: autonomy — unknown action '#{action}', denying for #{interaction_id}")
          result = %{decision: :denied, reason: "unknown_action: #{action}"}
          resolve_interaction(interaction_id, result, proxy_trail)
        else
          reason = "Proxy could not determine action: #{action || "unknown"}"
          escalate_to_human(interaction_id, reason)
        end
    end
  end

  defp resolve_interaction(interaction_id, result, proxy_trail) do
    AIBrain.Interaction.Manager.resolve(
      interaction_id,
      result,
      AIBrain.Data.Users.default_proxy_id(),
      proxy_trail: proxy_trail
    )
    Logger.info("Proxy: resolved interaction #{interaction_id} -> #{inspect(result)}")
  rescue
    e -> Logger.warning("Proxy: failed to resolve interaction: #{Exception.message(e)}")
  end

  defp publish_interaction_escalated(interaction_id, reason, proxy_trail) do
    event = AIBrain.Core.Events.interaction_escalated(interaction_id, reason, proxy_trail)
    AIBrain.Channel.Bus.publish(event)
    Logger.info("Proxy: escalated interaction #{interaction_id}: #{reason}")
  rescue
    e -> Logger.warning("Proxy: failed to publish interaction_escalated: #{Exception.message(e)}")
  end

  # ── Prompts ─────────────────────────────────────────────────

  defp run_review_prompt(ctx) do
    """
    #{AIBrain.Prompts.proxy_identity()}
    #{AIBrain.Prompts.proxy_decision_framework()}
    #{user_context_block()}

    ## Current State
    Goal: #{ctx[:goal_title] || "unknown"} (status: #{ctx[:goal_status] || "active"})
    Just completed: #{ctx[:task_title] || "unknown"}
    Output: #{truncate(ctx[:task_output], 300)}

    ## Available Actions
    - send_message → "message": "text to push the conversation forward"
    - continue → "next_task_title": "title" (creates a new task under the goal)
    - retry (re-runs this task)
    - complete (marks the goal done)
    - escalate → "reason": "why user must intervene"

    Before choosing: VERIFY your assessment. Check the output against the goal. Is there evidence
    of success or failure? If you can't verify through objective evidence, escalate.

    Reply with ONLY JSON: {"action":"...", "reason":"..."}
    """
  end

  # ── LLM ─────────────────────────────────────────────────────

  defp user_context_block do
    case AIBrain.User.profile_text() do
      "" -> ""
      text -> "\n## Who You Represent\n#{text}\n"
    end
  rescue
    _ -> ""
  end

  defp call_llm(prompt) do
    with {:ok, provider} <-
           AIBrain.Provider.SmartRouter.select(
             AIBrain.Provider.Router,
             %{model: nil, tools: [], turn: 0, retries: 0}
           ),
         messages = [%{role: "user", content: prompt}],
         {:ok, :streaming_complete} <-
           AIBrain.LLM.Client.stream(provider, messages, [], on_event: fn _ -> :ok end) do
      {:ok, collect_sse()}
    else
      err -> {:error, err}
    end
  rescue
    e -> {:error, e}
  end

  defp collect_sse(acc \\ "") do
    receive do
      {:sse_event, %{text: t}} -> collect_sse(acc <> t)
      {:sse_done} -> acc
    after
      30_000 -> acc
    end
  end

  # ── JSON ────────────────────────────────────────────────────

  defp extract_action(text) do
    text
    |> String.replace(~r/```json\s*/i, "")
    |> String.replace(~r/```\s*/i, "")
    |> String.trim()
    |> Jason.decode()
    |> case do
      {:ok, %{"action" => a}} -> a
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp extract_field(text, field) do
    text
    |> String.replace(~r/```json\s*/i, "")
    |> String.replace(~r/```\s*/i, "")
    |> String.trim()
    |> Jason.decode()
    |> case do
      {:ok, m} -> m[field]
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp truncate(nil, _), do: "(none)"
  defp truncate(s, n) when byte_size(s) <= n, do: s
  defp truncate(s, n), do: binary_part(s, 0, n) <> "..."

  defp proxy_active? do
    case AIBrain.Data.Users.get_proxy() do
      {:ok, %{active: true}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp proxy_autonomy? do
    case AIBrain.Data.Users.get_proxy() do
      {:ok, %{metadata: %{"autonomy" => true}}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
