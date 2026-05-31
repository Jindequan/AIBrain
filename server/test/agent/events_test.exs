defmodule AIBrain.Core.EventsTest do
  use ExUnit.Case, async: true

  alias AIBrain.Core.Events

  test "known_types/0 exposes the canonical runtime taxonomy" do
    types = Events.known_types()

    assert [
             :query_started,
             :provider_selected,
             :provider_failed,
             :capability_loaded,
             :capability_rejected,
             :marketplace_refreshed
             | _
           ] = types

    for type <- [
          :text_delta,
          :tool_start,
          :tool_result,
          :sandbox_feedback,
          :permission_checked,
          :turn_complete,
          :query_complete,
          :scheduler_item_fired,
          :task_completed,
          :delegation_completed,
          :thinking_delta,
          :context_truncated,
          :intent_classified,
          :intent_clarification_needed,
          :interaction_needed,
          :interaction_resolved,
          :feedback_submitted,
          :feedback_lesson_applied
        ] do
      assert type in types
    end
  end

  test "event helpers build stable payload shapes" do
    assert %{type: :query_started, session_id: "s1"} =
             Events.query_started(%{session_id: "s1"})

    assert %{
             type: :provider_selected,
             provider_name: "anthropic-primary",
             protocol: "anthropic",
             model: "claude-test"
           } = Events.provider_selected("anthropic-primary", "anthropic", "claude-test")

    assert %{
             type: :provider_failed,
             provider_name: "anthropic-primary",
             protocol: "anthropic",
             reason: {:http, 429},
             retry_at: 123.0
           } = Events.provider_failed("anthropic-primary", "anthropic", {:http, 429}, 123.0)

    assert %{type: :text_delta, text: "hello"} = Events.text_delta("hello")

    assert %{type: :capability_loaded, capability_name: "review-kit", source: :user} =
             Events.capability_loaded("review-kit", :user)

    assert %{
             type: :capability_rejected,
             capability_name: "workspace-kit",
             source: :project_local,
             reason: :project_local_disabled
           } =
             Events.capability_rejected("workspace-kit", :project_local, :project_local_disabled)

    assert %{type: :marketplace_refreshed, marketplace: "official", plugin_count: 2} =
             Events.marketplace_refreshed("official", 2)

    assert %{type: :tool_start, tool_name: "echo", tool_use_id: "t1"} =
             Events.tool_start("echo", "t1")

    assert %{type: :tool_result, tool_use_id: "t1", result: {:ok, "done"}} =
             Events.tool_result("t1", {:ok, "done"})

    assert %{
             type: :sandbox_feedback,
             tool_use_id: "t1",
             operation: :workspace_write,
             result: :blocked
           } =
             Events.sandbox_feedback("t1", :workspace_write, :blocked)

    assert %{type: :permission_checked, tool_name: "bash", decision: :denied, reason: :plan_mode} =
             Events.permission_checked("bash", :denied, :plan_mode)

    assert %{type: :memory_loaded, scope: :project, entry_count: 2} =
             Events.memory_loaded(:project, 2)

    assert %{type: :turn_complete, text: "done", stop_reason: "end_turn"} =
             Events.turn_complete("done", "end_turn")

    assert %{type: :query_complete, result: {:ok, "done"}} =
             Events.query_complete({:ok, "done"})

    assert %{type: :query_failed, reason: :timeout} =
             Events.query_failed(:timeout)

    assert %{type: :thinking_start, thinking_index: 0} =
             Events.thinking_start(0)

    assert %{type: :thinking_delta, thinking_index: 1, text: "reasoning..."} =
             Events.thinking_delta(1, "reasoning...")

    assert %{type: :thinking_end, thinking_index: 0} =
             Events.thinking_end(0)
  end

  test "interaction_needed promotes routing and display fields" do
    event =
      Events.interaction_needed(
        "int-1",
        :approval,
        %{"title" => "Authorization required", "reason" => "Workspace access needs approval"},
        %{run_id: "run-1", session_id: "session-1"}
      )

    assert event.type == :interaction_needed
    assert event.interaction_id == "int-1"
    assert event.run_id == "run-1"
    assert event.session_id == "session-1"
    assert event.title == "Authorization required"
    assert event.reason == "Workspace access needs approval"
  end

  test "type/1 returns the event type atom" do
    assert Events.type(Events.tool_start("echo", "t1")) == :tool_start
  end
end
