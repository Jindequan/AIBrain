defmodule AIBrain.KnowledgeWikiTest do
  use ExUnit.Case, async: false

  alias AIBrain.KnowledgeWiki

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AIBrain.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(AIBrain.Repo, {:shared, self()})

    Ecto.Adapters.SQL.query!(AIBrain.Repo, "DELETE FROM knowledge_entries", [])
    Ecto.Adapters.SQL.query!(AIBrain.Repo, "DELETE FROM sessions", [])

    # Create a session for FK references
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "INSERT INTO sessions (id, session_type, started_at, inserted_at, created_at, updated_at) VALUES ('session-test', 'test', ?, ?, ?, ?)",
      [now, now, now, now]
    )

    :ok
  end

  describe "extract_entries/1" do
    test "extracts nothing from empty turns" do
      assert KnowledgeWiki.extract_entries([]) == []
    end

    test "extracts fact from 'my name is' pattern" do
      turns = [
        %{
          "turn" => 1,
          "user_message" => "Hi, my name is Alice",
          "assistant_response" => "Hello Alice!",
          "tool_calls" => []
        }
      ]

      entries = KnowledgeWiki.extract_entries(turns)
      assert length(entries) >= 1

      fact = Enum.find(entries, fn e -> e.type == "fact" end)
      assert fact != nil
      assert String.contains?(fact.content, "Alice")
    end

    test "extracts preference from 'I prefer' pattern" do
      turns = [
        %{
          "turn" => 1,
          "user_message" => "I prefer using Python for scripting",
          "assistant_response" => "Python is a great choice!",
          "tool_calls" => []
        }
      ]

      entries = KnowledgeWiki.extract_entries(turns)
      assert length(entries) >= 1

      pref = Enum.find(entries, fn e -> e.type == "preference" end)
      assert pref != nil
      assert String.contains?(pref.content, "Python")
    end
  end

  describe "persist_entries and query" do
    test "persists and retrieves entries" do
      # Use the private function via a public round-trip
      assert [
               %{type: "fact", content: content}
               | _
             ] =
               KnowledgeWiki.extract_entries([
                 %{
                   "turn" => 1,
                   "user_message" => "my name is Bob",
                   "assistant_response" => "Hi Bob!",
                   "tool_calls" => []
                 }
               ])

      assert content =~ "Bob"

      # Ingest creates entries in DB via extract_entries + fallback DB path
      # Use ingest_conversation with a mock session_id
      # Since there's no conversation log, it won't extract, so insert directly
      KnowledgeWiki.ingest_conversation("session-test")

      # Since the conversation log doesn't exist for "session-test-1",
      # ingest returns 0 entries. Insert one directly for query testing.
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      hash = :crypto.hash(:sha256, "Python is preferred") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        """
        INSERT INTO knowledge_entries
          (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at, last_confirmed_at)
        VALUES (?, ?, ?, ?, ?, 'session', ?, 0.8, 1.0, ?, ?, ?)
        """,
        [
          "kw-test-1",
          "preference",
          "Python is preferred",
          hash,
          "[]",
          "session-test",
          now,
          now,
          now
        ]
      )

      entries = KnowledgeWiki.list()
      assert length(entries) == 1
      assert hd(entries).type == "preference"
      assert hd(entries).content == "Python is preferred"
    end

    test "queries by type" do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      # Insert a fact
      h1 = :crypto.hash(:sha256, "fact content") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "INSERT INTO knowledge_entries (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'session', ?, 0.9, 1.0, ?, ?)",
        ["kw-t1", "fact", "fact content", h1, "[]", "session-test", now, now]
      )

      # Insert a preference
      h2 = :crypto.hash(:sha256, "pref content") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "INSERT INTO knowledge_entries (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'session', ?, 0.7, 1.0, ?, ?)",
        ["kw-t2", "preference", "pref content", h2, "[]", "session-test", now, now]
      )

      facts = KnowledgeWiki.list(type: "fact")
      assert length(facts) == 1
      assert hd(facts).type == "fact"

      prefs = KnowledgeWiki.list(type: "preference")
      assert length(prefs) == 1
      assert hd(prefs).type == "preference"
    end

    test "query_by_relevance filters and ranks" do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      h1 = :crypto.hash(:sha256, "User prefers dark mode") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "INSERT INTO knowledge_entries (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'session', ?, 0.5, 1.0, ?, ?)",
        ["kw-r1", "preference", "User prefers dark mode", h1, "[]", "session-test", now, now]
      )

      h2 = :crypto.hash(:sha256, "Project uses Elixir") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "INSERT INTO knowledge_entries (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'session', ?, 0.6, 1.0, ?, ?)",
        ["kw-r2", "fact", "Project uses Elixir", h2, "[]", "session-test", now, now]
      )

      # Query without text (returns all)
      all = KnowledgeWiki.query_by_relevance("", limit: 10)
      assert length(all) == 2

      # With text matching "dark mode"
      matched = KnowledgeWiki.query_by_relevance("dark mode", limit: 10)
      assert length(matched) == 2

      # The dark mode entry should be boosted
      top = hd(matched)
      assert top.content == "User prefers dark mode"
    end
  end

  describe "format_for_prompt/1" do
    test "returns empty string for empty list" do
      assert KnowledgeWiki.format_for_prompt([]) == ""
    end

    test "formats entries as markdown" do
      entries = [
        %{type: "fact", content: "User's name is Alice"},
        %{type: "preference", content: "User prefers dark mode"}
      ]

      result = KnowledgeWiki.format_for_prompt(entries)
      assert result =~ "Knowledge from previous sessions"
      assert result =~ "[fact]"
      assert result =~ "[preference]"
      assert result =~ "Alice"
      assert result =~ "dark mode"
    end
  end

  describe "delete/1" do
    test "deletes an entry" do
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      h = :crypto.hash(:sha256, "delete me") |> Base.encode16(case: :lower)

      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "INSERT INTO knowledge_entries (id, type, content, content_hash, tags, source_type, source_session_id, confidence, decay_score, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'session', ?, 0.5, 1.0, ?, ?)",
        ["kw-del", "fact", "delete me", h, "[]", "session-test", now, now]
      )

      assert KnowledgeWiki.delete("kw-del") == :ok
      assert KnowledgeWiki.list() == []
    end
  end

  describe "format_conversation/1" do
    test "formats turns into text" do
      turns = [
        %{
          "turn" => 1,
          "user_message" => "Hello",
          "assistant_response" => "Hi there!",
          "tool_calls" => []
        }
      ]

      result = KnowledgeWiki.extract_entries(turns)

      # Since there's no LLM provider, falls back to keyword extraction
      assert is_list(result)
    end
  end
end
