defmodule AIBrain.AgentRuntime.GoalMetadataIntegrationTest do
  use AIBrain.DataCase

  alias AIBrain.AgentRuntime.GoalMetadata
  alias AIBrain.Data.Goals

  describe "GoalMetadata reads flat canonical keys" do
    test "current_strategy reads flat key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "current_strategy" => "Proceed with plan A",
            "autonomous" => true,
            "autonomy_level" => 1
          }
        })

      assert GoalMetadata.current_strategy(goal) == "Proceed with plan A"
    end

    test "next_actions reads flat key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "next_actions" => ["action1", "action2"],
            "autonomous" => true
          }
        })

      assert GoalMetadata.next_actions(goal) == ["action1", "action2"]
    end

    test "blockers reads flat key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "blockers" => ["waiting for API key"],
            "autonomous" => true
          }
        })

      assert GoalMetadata.blockers(goal) == ["waiting for API key"]
    end

    test "next_review_at reads flat key" do
      review_time = "2026-06-01T12:00:00Z"

      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "next_review_at" => review_time,
            "autonomous" => true
          }
        })

      assert GoalMetadata.next_review_at(goal) == review_time
    end

    test "last_report reads flat key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "last_report" => "2026-05-19T10:00:00Z",
            "autonomous" => true
          }
        })

      assert GoalMetadata.last_report(goal) == "2026-05-19T10:00:00Z"
    end

    test "needs_owner_input? reads flat key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "needs_owner_input" => true,
            "autonomous" => true
          }
        })

      assert GoalMetadata.needs_owner_input?(goal) == true
    end

    test "needs_owner_input? returns false when not set" do
      {:ok, goal} =
        Goals.create(%{
          title: "Test Goal",
          status: "active",
          metadata: %{
            "autonomous" => true
          }
        })

      assert GoalMetadata.needs_owner_input?(goal) == false
    end
  end

  describe "GoalMetadata falls back to legacy nested keys" do
    test "current_strategy falls back to legacy strategy key" do
      {:ok, goal} =
        Goals.create(%{
          title: "Legacy Goal",
          status: "active",
          metadata: %{
            "strategy" => %{"current_assessment" => "Old plan"},
            "autonomous" => true
          }
        })

      # Should read from legacy path since no flat key
      assert GoalMetadata.current_strategy(goal) == "Old plan"
    end

    test "current_strategy returns empty string when nothing is set" do
      {:ok, goal} =
        Goals.create(%{
          title: "Empty Goal",
          status: "active",
          metadata: %{"autonomous" => true}
        })

      assert GoalMetadata.current_strategy(goal) == ""
    end
  end

  describe "enrich_metadata copies legacy to flat keys" do
    test "enrich_metadata copies strategy fields to flat keys" do
      {:ok, goal} =
        Goals.create(%{
          title: "Enrich Test",
          status: "active",
          metadata: %{
            "strategy" => %{
              "current_assessment" => "Enriched plan",
              "next_actions" => ["a", "b"],
              "blockers" => ["blocker1"],
              "needs_owner_input" => true,
              "last_report" => "2026-05-01"
            },
            "autonomous" => true
          }
        })

      enriched = GoalMetadata.enrich_metadata(goal)

      assert enriched["current_strategy"] == "Enriched plan"
      assert enriched["next_actions"] == ["a", "b"]
      assert enriched["blockers"] == ["blocker1"]
      assert enriched["needs_owner_input"] == true
      assert enriched["last_report"] == "2026-05-01"
    end
  end
end
