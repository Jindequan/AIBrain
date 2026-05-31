defmodule AIBrain.Engine.ResultSink.PlanSinkTest do
  use ExUnit.Case

  alias AIBrain.Engine.ResultSink.PlanSink

  setup do
    if :ets.whereis(:plan_sink_events) != :undefined do
      :ets.delete(:plan_sink_events)
    end

    :ok
  end

  describe "questions" do
    test "store_question and pop_questions round-trip" do
      PlanSink.store_question("plan-1", "What is the priority?")
      PlanSink.store_question("plan-1", "Who should be assigned?")
      result = PlanSink.pop_questions("plan-1")
      assert length(result) == 2
      assert "What is the priority?" in result
      assert "Who should be assigned?" in result
      assert PlanSink.pop_questions("plan-1") == []
    end

    test "pop_questions scoped to tx_id" do
      PlanSink.store_question("plan-1", "Question A")
      PlanSink.store_question("plan-2", "Question B")
      assert PlanSink.pop_questions("plan-1") == ["Question A"]
      assert PlanSink.pop_questions("plan-2") == ["Question B"]
    end
  end

  describe "save_result and load" do
    test "save_result stores ok result" do
      assert PlanSink.save_result("plan-1", {:ok, "done"}) == :ok
      assert PlanSink.load("plan-1") == {:ok, %{result: :ok, text: "done"}}
    end

    test "save_result stores error result" do
      assert PlanSink.save_result("plan-1", {:error, "failed"}) == :ok
      assert PlanSink.load("plan-1") == {:ok, %{result: :error, reason: "failed"}}
    end

    test "load returns not_found for unknown" do
      assert PlanSink.load("unknown") == {:error, :not_found}
    end
  end
end
