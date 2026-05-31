defmodule AIBrain.Memory.UserProfileTest do
  use ExUnit.Case, async: true

  alias AIBrain.Memory.{Entry, UserProfile}

  describe "load/0" do
    test "returns a struct even when no profile file exists" do
      profile = UserProfile.load()
      assert %UserProfile{} = profile
    end
  end

  describe "format_for_prompt/1" do
    test "returns empty string for empty profile" do
      profile = %UserProfile{}
      assert UserProfile.format_for_prompt(profile) == ""
    end

    test "includes name when present" do
      profile = %UserProfile{name: "Devin"}
      result = UserProfile.format_for_prompt(profile)
      assert String.contains?(result, "Devin")
      assert String.contains?(result, "Name")
    end

    test "includes current phase when present" do
      profile = %UserProfile{current_phase: "Building AIBrain"}
      result = UserProfile.format_for_prompt(profile)
      assert String.contains?(result, "Building AIBrain")
    end

    test "includes preferences when present" do
      profile = %UserProfile{
        preferences: %{"communication_style" => "concise", "code_style" => "functional"}
      }

      result = UserProfile.format_for_prompt(profile)
      assert String.contains?(result, "concise")
      assert String.contains?(result, "functional")
    end
  end

  describe "update_from_entries/2" do
    test "extracts preference entries" do
      profile = %UserProfile{}

      entries = [
        Entry.new(%{
          id: "1",
          source: :knowledge_wiki,
          type: :preference,
          content: "User prefers concise and direct responses",
          confidence: 0.8
        })
      ]

      updated = UserProfile.update_from_entries(profile, entries)
      assert updated.preferences["communication_style"] == "concise"
    end

    test "extracts name from fact entries" do
      profile = %UserProfile{}

      entries = [
        Entry.new(%{
          id: "2",
          source: :knowledge_wiki,
          type: :fact,
          content: "User's name is Devin",
          confidence: 0.9
        })
      ]

      updated = UserProfile.update_from_entries(profile, entries)
      assert updated.name == "Devin"
    end

    test "extracts phase from task_outcome entries" do
      profile = %UserProfile{}

      entries = [
        Entry.new(%{
          id: "3",
          source: :knowledge_wiki,
          type: :task_outcome,
          content: "Completed AIBrain memory system implementation",
          confidence: 0.9
        })
      ]

      updated = UserProfile.update_from_entries(profile, entries)
      assert updated.current_phase == "Building AIBrain"
    end
  end
end
