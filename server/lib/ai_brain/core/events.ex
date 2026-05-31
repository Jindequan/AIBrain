defmodule AIBrain.Core.Events do
  @moduledoc """
  Canonical runtime event shapes shared across the agent runtime.

  Defines canonical event names for the unified agent runtime.
  """

  @type event_type ::
          :query_started
          | :provider_selected
          | :provider_failed
          | :capability_loaded
          | :capability_rejected
          | :marketplace_refreshed
          | :text_delta
          | :tool_start
          | :tool_use_start_sse
          | :tool_result
          | :tool_crashed
          | :tool_exited
          | :tool_threw
          | :sandbox_feedback
          | :permission_checked
          | :memory_loaded
          | :turn_complete
          | :query_complete
          | :query_failed
          | :scheduler_wake
          | :scheduler_item_created
          | :scheduler_item_fired
          | :scheduler_item_cancelled
          | :workspace_bootstrapped
          | :task_started
          | :task_progress
          | :task_completed
          | :task_failed
          | :task_killed
          | :delegation_started
          | :delegation_worker_started
          | :delegation_worker_completed
          | :delegation_worker_failed
          | :delegation_completed
          | :delegation_failed
          | :thinking_start
          | :thinking_delta
          | :thinking_end
          | :context_truncated
          | :intent_classified
          | :intent_clarification_needed
          | :intent_confirmed
          | :intent_executing
          | :intent_completed
          | :intent_failed
          | :interaction_needed
          | :interaction_resolved
          | :interaction_escalated
          | :interaction_expired
          | :feedback_submitted
          | :feedback_lesson_applied

  @type event :: %{required(:type) => event_type(), optional(atom()) => any()}

  @known_types [
    :query_started,
    :provider_selected,
    :provider_failed,
    :capability_loaded,
    :capability_rejected,
    :marketplace_refreshed,
    :text_delta,
    :tool_start,
    :tool_use_start_sse,
    :tool_result,
    :tool_crashed,
    :tool_exited,
    :tool_threw,
    :sandbox_feedback,
    :permission_checked,
    :memory_loaded,
    :turn_complete,
    :query_complete,
    :query_failed,
    :scheduler_wake,
    :scheduler_item_created,
    :scheduler_item_fired,
    :scheduler_item_cancelled,
    :workspace_bootstrapped,
    :task_started,
    :task_progress,
    :task_completed,
    :task_failed,
    :task_killed,
    :delegation_started,
    :delegation_worker_started,
    :delegation_worker_completed,
    :delegation_worker_failed,
    :delegation_completed,
    :delegation_failed,
    :thinking_start,
    :thinking_delta,
    :thinking_end,
    :context_truncated,
    :intent_classified,
    :intent_clarification_needed,
    :intent_confirmed,
    :intent_executing,
    :intent_completed,
    :intent_failed,
    :interaction_needed,
    :interaction_resolved,
    :interaction_escalated,
    :interaction_expired,
    :feedback_submitted,
    :feedback_lesson_applied
  ]

  def known_types, do: @known_types

  def type(%{type: type}), do: type

  def enrich(event, attrs) when is_map(event) and is_map(attrs), do: Map.merge(event, attrs)

  def query_started(attrs \\ %{}), do: Map.merge(%{type: :query_started}, attrs)

  def provider_selected(provider_name, protocol, model) do
    %{
      type: :provider_selected,
      provider_name: provider_name,
      protocol: protocol,
      model: model
    }
  end

  def provider_failed(provider_name, protocol, reason, retry_at \\ nil) do
    %{
      type: :provider_failed,
      provider_name: provider_name,
      protocol: protocol,
      reason: reason,
      retry_at: retry_at
    }
  end

  def capability_loaded(capability_name, source, attrs \\ %{}) do
    Map.merge(
      %{type: :capability_loaded, capability_name: capability_name, source: source},
      attrs
    )
  end

  def capability_rejected(capability_name, source, reason, attrs \\ %{}) do
    Map.merge(
      %{
        type: :capability_rejected,
        capability_name: capability_name,
        source: source,
        reason: reason
      },
      attrs
    )
  end

  def marketplace_refreshed(marketplace, plugin_count, attrs \\ %{}) do
    Map.merge(
      %{type: :marketplace_refreshed, marketplace: marketplace, plugin_count: plugin_count},
      attrs
    )
  end

  def text_delta(text), do: %{type: :text_delta, text: text}

  def tool_start(tool_name, tool_use_id, input \\ nil) do
    event = %{type: :tool_start, tool_name: tool_name, tool_use_id: tool_use_id}
    if input, do: Map.put(event, :input, input), else: event
  end

  def tool_result(tool_use_id, result) do
    %{type: :tool_result, tool_use_id: tool_use_id, result: result}
  end

  def sandbox_feedback(tool_use_id, operation, result, attrs \\ %{}) do
    Map.merge(
      %{type: :sandbox_feedback, tool_use_id: tool_use_id, operation: operation, result: result},
      attrs
    )
  end

  def permission_checked(tool_name, decision, reason \\ nil, attrs \\ %{}) do
    Map.merge(
      %{type: :permission_checked, tool_name: tool_name, decision: decision, reason: reason},
      attrs
    )
  end

  def memory_loaded(scope, entry_count \\ nil) do
    %{type: :memory_loaded, scope: scope, entry_count: entry_count}
  end

  def turn_complete(text, stop_reason) do
    %{type: :turn_complete, text: text, stop_reason: stop_reason}
  end

  def query_complete(result), do: %{type: :query_complete, result: result}

  def query_failed(reason), do: %{type: :query_failed, reason: reason}

  def scheduler_wake(cause, item_id, attrs \\ %{}) do
    Map.merge(%{type: :scheduler_wake, cause: cause, item_id: item_id}, attrs)
  end

  def scheduler_item_created(item_id, type, attrs \\ %{}) do
    Map.merge(%{type: :scheduler_item_created, item_id: item_id, schedule_type: type}, attrs)
  end

  def scheduler_item_fired(item_id, type, action, attrs \\ %{}) do
    Map.merge(
      %{type: :scheduler_item_fired, item_id: item_id, schedule_type: type, action: action},
      attrs
    )
  end

  def scheduler_item_cancelled(item_id, attrs \\ %{}) do
    Map.merge(%{type: :scheduler_item_cancelled, item_id: item_id}, attrs)
  end

  def workspace_bootstrapped(attrs \\ %{}) do
    Map.merge(%{type: :workspace_bootstrapped}, attrs)
  end

  def task_started(task_id, type, description, attrs \\ %{}) do
    Map.merge(
      %{type: :task_started, task_id: task_id, task_type: type, description: description},
      attrs
    )
  end

  def task_progress(task_id, output_chunk, attrs \\ %{}) do
    Map.merge(%{type: :task_progress, task_id: task_id, output_chunk: output_chunk}, attrs)
  end

  def task_completed(task_id, exit_code, duration_ms, attrs \\ %{}) do
    Map.merge(
      %{type: :task_completed, task_id: task_id, exit_code: exit_code, duration_ms: duration_ms},
      attrs
    )
  end

  def task_failed(task_id, exit_code, reason, attrs \\ %{}) do
    Map.merge(
      %{type: :task_failed, task_id: task_id, exit_code: exit_code, reason: reason},
      attrs
    )
  end

  def task_killed(task_id, attrs \\ %{}) do
    Map.merge(%{type: :task_killed, task_id: task_id}, attrs)
  end

  def delegation_started(plan_id, sub_task_count, attrs \\ %{}) do
    Map.merge(
      %{type: :delegation_started, plan_id: plan_id, sub_task_count: sub_task_count},
      attrs
    )
  end

  def delegation_worker_started(plan_id, worker_id, worker_type, attrs \\ %{}) do
    Map.merge(
      %{
        type: :delegation_worker_started,
        plan_id: plan_id,
        worker_id: worker_id,
        worker_type: worker_type
      },
      attrs
    )
  end

  def delegation_worker_completed(plan_id, worker_id, attrs \\ %{}) do
    Map.merge(
      %{type: :delegation_worker_completed, plan_id: plan_id, worker_id: worker_id},
      attrs
    )
  end

  def delegation_worker_failed(plan_id, worker_id, reason, attrs \\ %{}) do
    Map.merge(
      %{type: :delegation_worker_failed, plan_id: plan_id, worker_id: worker_id, reason: reason},
      attrs
    )
  end

  def delegation_completed(plan_id, attrs \\ %{}) do
    Map.merge(%{type: :delegation_completed, plan_id: plan_id}, attrs)
  end

  def delegation_failed(plan_id, reason, attrs \\ %{}) do
    Map.merge(%{type: :delegation_failed, plan_id: plan_id, reason: reason}, attrs)
  end

  # -- Thinking (extended thinking / reasoning) events --

  def thinking_start(thinking_index \\ 0) do
    %{type: :thinking_start, thinking_index: thinking_index}
  end

  def thinking_delta(thinking_index, text) do
    %{type: :thinking_delta, thinking_index: thinking_index, text: text}
  end

  def thinking_end(thinking_index, thinking_text \\ nil) do
    event = %{type: :thinking_end, thinking_index: thinking_index}
    if thinking_text, do: Map.put(event, :text, thinking_text), else: event
  end

  # -- Intent events --

  def intent_classified(intent_id, intent_type, confidence, session_id) do
    %{
      type: :intent_classified,
      intent_id: intent_id,
      intent_type: intent_type,
      confidence: confidence,
      session_id: session_id
    }
  end

  def intent_clarification_needed(intent_id, questions, session_id) do
    %{
      type: :intent_clarification_needed,
      intent_id: intent_id,
      questions: questions,
      session_id: session_id
    }
  end

  def intent_confirmed(intent_id, skill_id, intent_type) do
    %{
      type: :intent_confirmed,
      intent_id: intent_id,
      skill_id: skill_id,
      intent_type: intent_type
    }
  end

  def intent_executing(intent_id, skill_id) do
    %{
      type: :intent_executing,
      intent_id: intent_id,
      skill_id: skill_id
    }
  end

  def intent_completed(intent_id, result, run_id) do
    %{
      type: :intent_completed,
      intent_id: intent_id,
      result: result,
      run_id: run_id
    }
  end

  def intent_failed(intent_id, reason, recoverable) do
    %{
      type: :intent_failed,
      intent_id: intent_id,
      reason: reason,
      recoverable: recoverable
    }
  end

  # -- Interaction events --

  def interaction_needed(interaction_id, interaction_type, schema, context, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    schema = schema || %{}
    context = context || %{}

    Map.merge(
      %{
        type: :interaction_needed,
        interaction_id: interaction_id,
        interaction_type: interaction_type,
        schema: schema,
        context: context,
        run_id: context[:run_id] || context["run_id"],
        session_id: context[:session_id] || context["session_id"],
        title: schema[:title] || schema["title"],
        reason: schema[:reason] || schema["reason"]
      },
      attrs
    )
  end

  def interaction_resolved(interaction_id, result, resolved_by, attrs \\ %{}) do
    Map.merge(
      %{
        type: :interaction_resolved,
        interaction_id: interaction_id,
        result: result,
        resolved_by: resolved_by
      },
      attrs
    )
  end

  def interaction_escalated(interaction_id, reason, proxy_trail, attrs \\ %{}) do
    Map.merge(
      %{
        type: :interaction_escalated,
        interaction_id: interaction_id,
        reason: reason,
        proxy_trail: proxy_trail
      },
      attrs
    )
  end

  # -- Feedback events --

  def interaction_expired(interaction_id, interaction_type, attrs \\ %{}) do
    Map.merge(
      %{
        type: :interaction_expired,
        interaction_id: interaction_id,
        interaction_type: interaction_type
      },
      attrs
    )
  end

  def feedback_submitted(feedback_id, target_type, severity, attrs \\ %{}) do
    Map.merge(
      %{
        type: :feedback_submitted,
        feedback_id: feedback_id,
        target_type: target_type,
        severity: severity
      },
      attrs
    )
  end

  def feedback_lesson_applied(lesson_id, target_type, attrs \\ %{}) do
    Map.merge(
      %{
        type: :feedback_lesson_applied,
        lesson_id: lesson_id,
        target_type: target_type
      },
      attrs
    )
  end
end
