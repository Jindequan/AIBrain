defmodule AIBrain.AgentRuntime.GoalMetadataTest do
  use AIBrain.DataCase

  alias AIBrain.AgentRuntime.GoalMetadata

  describe "current_strategy/1" do
    test "reads from canonical key" do
      meta = %{"current_strategy" => "On track"}
      assert GoalMetadata.current_strategy(meta) == "On track"
    end

    test "falls back to legacy strategy.current_assessment" do
      meta = %{"strategy" => %{"current_assessment" => "Needs attention"}}
      assert GoalMetadata.current_strategy(meta) == "Needs attention"
    end

    test "prefers canonical over legacy" do
      meta = %{
        "current_strategy" => "Canonical",
        "strategy" => %{"current_assessment" => "Legacy"}
      }

      assert GoalMetadata.current_strategy(meta) == "Canonical"
    end

    test "returns empty string when absent" do
      assert GoalMetadata.current_strategy(%{}) == ""
    end
  end

  describe "next_actions/1" do
    test "reads from canonical key" do
      meta = %{"next_actions" => ["Action A", "Action B"]}
      assert GoalMetadata.next_actions(meta) == ["Action A", "Action B"]
    end

    test "falls back to legacy strategy.next_actions" do
      meta = %{"strategy" => %{"next_actions" => ["Legacy action"]}}
      assert GoalMetadata.next_actions(meta) == ["Legacy action"]
    end

    test "returns empty list when absent" do
      assert GoalMetadata.next_actions(%{}) == []
    end
  end

  describe "blockers/1" do
    test "reads from canonical key" do
      meta = %{"blockers" => ["Blocker 1"]}
      assert GoalMetadata.blockers(meta) == ["Blocker 1"]
    end

    test "falls back to legacy strategy.blockers" do
      meta = %{"strategy" => %{"blockers" => ["Legacy blocker"]}}
      assert GoalMetadata.blockers(meta) == ["Legacy blocker"]
    end

    test "returns empty list when absent" do
      assert GoalMetadata.blockers(%{}) == []
    end
  end

  describe "next_review_at/1" do
    test "reads from canonical key" do
      meta = %{"next_review_at" => "2026-06-01T00:00:00Z"}
      assert GoalMetadata.next_review_at(meta) == "2026-06-01T00:00:00Z"
    end

    test "falls back to legacy next_review_after" do
      meta = %{"next_review_after" => "2026-06-01T00:00:00Z"}
      assert GoalMetadata.next_review_at(meta) == "2026-06-01T00:00:00Z"
    end

    test "returns nil when absent" do
      assert GoalMetadata.next_review_at(%{}) == nil
    end
  end

  describe "last_report/1" do
    test "reads from canonical key" do
      meta = %{"last_report" => "2026-05-15T10:00:00Z"}
      assert GoalMetadata.last_report(meta) == "2026-05-15T10:00:00Z"
    end

    test "returns nil when absent" do
      assert GoalMetadata.last_report(%{}) == nil
    end
  end

  describe "needs_owner_input?/1" do
    test "reads from canonical key" do
      meta = %{"needs_owner_input" => true}
      assert GoalMetadata.needs_owner_input?(meta) == true
    end

    test "falls back to legacy strategy.needs_owner_input" do
      meta = %{"strategy" => %{"needs_owner_input" => true}}
      assert GoalMetadata.needs_owner_input?(meta) == true
    end

    test "returns false when absent" do
      assert GoalMetadata.needs_owner_input?(%{}) == false
    end
  end

  describe "works with goal struct" do
    test "reads metadata from goal map with metadata key" do
      {:ok, goal} =
        AIBrain.Data.Goals.create(%{
          title: "Test Goal",
          status: "active",
          priority: 1,
          metadata: %{
            "current_strategy" => "Making progress",
            "next_actions" => ["Step 1"],
            "blockers" => [],
            "next_review_at" => "2026-06-01T00:00:00Z",
            "last_report" => "2026-05-15T00:00:00Z"
          }
        })

      assert GoalMetadata.current_strategy(goal) == "Making progress"
      assert GoalMetadata.next_actions(goal) == ["Step 1"]
      assert GoalMetadata.blockers(goal) == []
      assert GoalMetadata.next_review_at(goal) == "2026-06-01T00:00:00Z"
      assert GoalMetadata.last_report(goal) == "2026-05-15T00:00:00Z"
    end

    test "reads metadata from legacy goal struct" do
      {:ok, goal} =
        AIBrain.Data.Goals.create(%{
          title: "Legacy Goal",
          status: "active",
          priority: 1,
          metadata: %{
            "strategy" => %{
              "current_assessment" => "Legacy assessment",
              "next_actions" => ["Legacy action"],
              "blockers" => ["Legacy blocker"]
            },
            "next_review_after" => "2026-07-01T00:00:00Z"
          }
        })

      assert GoalMetadata.current_strategy(goal) == "Legacy assessment"
      assert GoalMetadata.next_actions(goal) == ["Legacy action"]
      assert GoalMetadata.blockers(goal) == ["Legacy blocker"]
      assert GoalMetadata.next_review_at(goal) == "2026-07-01T00:00:00Z"
    end
  end

  describe "summary/1" do
    test "returns all standardized fields" do
      meta = %{
        "current_strategy" => "All good",
        "next_actions" => ["A"],
        "blockers" => [],
        "next_review_at" => "2026-06-01T00:00:00Z",
        "last_report" => "2026-05-01T00:00:00Z"
      }

      s = GoalMetadata.summary(meta)
      assert s.current_strategy == "All good"
      assert s.next_actions == ["A"]
      assert s.blockers == []
      assert s.next_review_at == "2026-06-01T00:00:00Z"
      assert s.last_report == "2026-05-01T00:00:00Z"
    end

    test "handles nil metadata gracefully" do
      s = GoalMetadata.summary(nil)
      assert s.current_strategy == ""
      assert s.next_actions == []
      assert s.blockers == []
      assert s.next_review_at == nil
    end
  end

  describe "enrich_metadata/2" do
    test "copies legacy strategy keys to canonical flat keys" do
      meta = %{"strategy" => %{"current_assessment" => "Test", "next_actions" => ["X"], "blockers" => ["Y"]}}
      enriched = GoalMetadata.enrich_metadata(meta)

      assert enriched["current_strategy"] == "Test"
      assert enriched["next_actions"] == ["X"]
      assert enriched["blockers"] == ["Y"]
    end

    test "copies next_review_after to next_review_at" do
      meta = %{"next_review_after" => "2026-07-01T00:00:00Z"}
      enriched = GoalMetadata.enrich_metadata(meta)

      assert enriched["next_review_at"] == "2026-07-01T00:00:00Z"
    end

    test "does not overwrite existing canonical keys" do
      meta = %{
        "current_strategy" => "Canonical",
        "strategy" => %{"current_assessment" => "Legacy"}
      }

      enriched = GoalMetadata.enrich_metadata(meta)
      assert enriched["current_strategy"] == "Canonical"
    end
  end
end
