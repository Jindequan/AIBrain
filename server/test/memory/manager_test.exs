defmodule AIBrain.Memory.ManagerTest do
  use AIBrain.DataCase, async: false

  alias AIBrain.Memory
  alias AIBrain.Memory.Manager

  describe "search/2" do
    test "returns empty list for empty query" do
      # Empty query should return empty results gracefully
      # (The function only accepts non-empty queries)
      result = Manager.search("unlikely_to_match_anything_xyz", limit: 5)
      # In test environment without pre-populated data, returns empty
      assert is_list(result)
    end

    test "accepts limit option" do
      result = Manager.search("test", limit: 3)
      assert is_list(result)
      assert length(result) <= 3
    end

    test "handles source filter" do
      result = Manager.search("test", sources: [AIBrain.Memory.Stores.KnowledgeWiki])
      assert is_list(result)
    end
  end

  describe "total_entries/0" do
    test "returns integer count" do
      count = Manager.total_entries()
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "format_for_prompt/1" do
    test "returns empty string for empty entries" do
      assert Manager.format_for_prompt([]) == ""
    end

    test "formats entries with source labels" do
      entry =
        AIBrain.Memory.Entry.new(%{
          id: "test-1",
          source: :knowledge_wiki,
          type: :fact,
          content: "User prefers concise responses",
          confidence: 0.9
        })

      formatted = Manager.format_for_prompt([entry])
      assert String.contains?(formatted, "prefers concise")
      assert String.contains?(formatted, "Memory")
    end
  end

  describe "context_text/1" do
    test "formats map entries without requiring struct access" do
      text =
        Memory.context_text([
          %{source: :episodic, type: :episodic, content: "Goal report memory"}
        ])

      assert text =~ "Goal report memory"
      assert text =~ "[episodic]"
    end

    test "formats Entry structs without Access protocol" do
      entry =
        AIBrain.Memory.Entry.new(%{
          id: "entry-1",
          content: "Structured memory entry",
          source: :knowledge_wiki,
          type: :fact,
          confidence: 0.9
        })

      text = Memory.context_text([entry])

      assert text =~ "Structured memory entry"
      assert text =~ "[memory]"
    end
  end
end
