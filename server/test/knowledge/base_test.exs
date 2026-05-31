defmodule AIBrain.Knowledge.BaseTest do
  use ExUnit.Case, async: true

  alias AIBrain.Knowledge.Base

  describe "format_for_prompt/1" do
    test "formats knowledge entry with all fields" do
      knowledge = %Base{
        id: "test",
        category: :scientific,
        domain: "general",
        title: "Test Knowledge",
        content: "This is test content.",
        principles: ["Principle 1", "Principle 2"],
        examples: "Example content",
        tags: ["test"],
        applicable_intents: ["all"],
        version: "1.0"
      }

      formatted = Base.format_for_prompt(knowledge)

      assert formatted =~ "## Test Knowledge"
      assert formatted =~ "This is test content."
      assert formatted =~ "- Principle 1"
      assert formatted =~ "- Principle 2"
      assert formatted =~ "**示例：**"
      assert formatted =~ "Example content"
    end

    test "handles empty examples" do
      knowledge = %Base{
        id: "test",
        category: :engineering,
        domain: "software",
        title: "Test",
        content: "Content",
        principles: ["P1"],
        examples: "",
        tags: [],
        applicable_intents: ["all"],
        version: "1.0"
      }

      formatted = Base.format_for_prompt(knowledge)

      refute formatted =~ "**示例：**"
    end
  end

  describe "applicable?/3" do
    test "matches when intent in applicable_intents" do
      knowledge = %Base{
        applicable_intents: ["debugging", "troubleshooting"],
        tags: ["all"]
      }

      assert Base.applicable?(knowledge, :debugging, nil)
      assert Base.applicable?(knowledge, "debugging", nil)
      refute Base.applicable?(knowledge, :coding, nil)
    end

    test "matches when applicable_intents contains 'all'" do
      knowledge = %Base{
        applicable_intents: ["all"],
        tags: ["all"]
      }

      assert Base.applicable?(knowledge, :any_intent, nil)
      assert Base.applicable?(knowledge, "debugging", nil)
    end

    test "matches when domain matches tags" do
      knowledge = %Base{
        applicable_intents: ["all"],
        tags: ["software", "backend"]
      }

      assert Base.applicable?(knowledge, :debugging, "software")
      assert Base.applicable?(knowledge, :debugging, "backend")
      refute Base.applicable?(knowledge, :debugging, "design")
    end

    test "matches when tags contains 'all'" do
      knowledge = %Base{
        applicable_intents: ["all"],
        tags: ["all"]
      }

      assert Base.applicable?(knowledge, :debugging, "any_domain")
    end

    test "requires both intent and domain match" do
      knowledge = %Base{
        applicable_intents: ["debugging"],
        tags: ["backend"]
      }

      # Both match
      assert Base.applicable?(knowledge, :debugging, "backend")

      # Intent doesn't match
      refute Base.applicable?(knowledge, :coding, "backend")

      # Domain doesn't match
      refute Base.applicable?(knowledge, :debugging, "frontend")

      # Neither matches
      refute Base.applicable?(knowledge, :coding, "frontend")
    end
  end
end
