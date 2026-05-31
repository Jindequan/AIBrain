defmodule AIBrain.Memory.DistillerTest do
  use AIBrain.DataCase, async: false

  alias AIBrain.Data.EpisodicMemories
  alias AIBrain.Memory.Distiller

  describe "goal_lessons/2" do
    test "returns empty list when goal has no episodes" do
      assert Distiller.goal_lessons("nonexistent-goal") == []
    end

    test "aggregates and deduplicates lessons across episodes" do
      goal_id = Ecto.UUID.generate()

      {:ok, _} =
        EpisodicMemories.create(%{
          goal_id: goal_id,
          narrative: "First run",
          lessons: ["Always validate inputs", "Use proper error handling"],
          success_score: 0.8
        })

      {:ok, _} =
        EpisodicMemories.create(%{
          goal_id: goal_id,
          narrative: "Second run",
          lessons: ["Always validate inputs", "Cache external API responses"],
          success_score: 0.9
        })

      lessons = Distiller.goal_lessons(goal_id, limit: 10)
      assert "Always validate inputs" in lessons
      assert "Use proper error handling" in lessons
      assert "Cache external API responses" in lessons
      # "Always validate inputs" should only appear once (dedup)
      assert Enum.count(lessons, &(&1 == "Always validate inputs")) == 1
    end

    test "respects limit option" do
      goal_id = Ecto.UUID.generate()

      {:ok, _} =
        EpisodicMemories.create(%{
          goal_id: goal_id,
          narrative: "Run",
          lessons: ["Lesson A", "Lesson B", "Lesson C", "Lesson D", "Lesson E", "Lesson F"],
          success_score: 0.5
        })

      lessons = Distiller.goal_lessons(goal_id, limit: 3)
      assert length(lessons) <= 3
    end
  end

  describe "memory_context/2" do
    test "returns empty string for goal with no episodes" do
      assert Distiller.memory_context("nonexistent-goal") == ""
    end

    test "builds context string with narrative and lessons" do
      goal_id = Ecto.UUID.generate()

      {:ok, _} =
        EpisodicMemories.create(%{
          goal_id: goal_id,
          narrative: "Successfully deployed the API with monitoring",
          lessons: ["Monitor memory usage", "Set up alerts before deploying"],
          success_score: 0.9,
          key_decisions: %{"decision" => "Use Redis", "rationale" => "Low latency caching"}
        })

      context = Distiller.memory_context(goal_id, limit: 3)
      assert context =~ "Goal History"
      assert context =~ "deployed"
      assert context =~ "Monitor memory usage"
      assert context =~ "Set up alerts"
    end

    test "respects limit option" do
      goal_id = Ecto.UUID.generate()

      for i <- 1..5 do
        {:ok, _} =
          EpisodicMemories.create(%{
            goal_id: goal_id,
            narrative: "Episode #{i}",
            lessons: ["Lesson #{i}"],
            success_score: 0.5
          })
      end

      context = Distiller.memory_context(goal_id, limit: 2)
      # Should only mention 2 episodes
      assert context =~ "2 episodes"
    end
  end

  describe "dedup_lessons/2" do
    test "removes near-duplicate lessons" do
      lessons = [
        "Always validate user input before processing",
        "Always validate user input before processing the request",
        "Cache responses for performance",
        "Cache responses for better performance"
      ]

      deduped = Distiller.dedup_lessons(lessons)
      # Should collapse very similar lessons (high Jaccard overlap)
      assert length(deduped) <= 3
      assert Enum.any?(deduped, &String.contains?(&1, "validate"))
      assert Enum.any?(deduped, &String.contains?(&1, "Cache"))
    end

    test "keeps clearly different lessons" do
      lessons = [
        "Use proper error handling",
        "Cache API responses",
        "Monitor memory usage"
      ]

      deduped = Distiller.dedup_lessons(lessons)
      assert length(deduped) == 3
    end

    test "returns empty list for empty input" do
      assert Distiller.dedup_lessons([]) == []
    end

    test "filters blank strings" do
      lessons = ["", "  ", "Valid lesson"]
      assert Distiller.dedup_lessons(lessons) == ["Valid lesson"]
    end
  end
end
