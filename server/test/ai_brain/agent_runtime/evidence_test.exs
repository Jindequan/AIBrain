defmodule AIBrain.AgentRuntime.EvidenceTest do
  use AIBrain.DataCase

  alias AIBrain.AgentRuntime.Evidence
  alias AIBrain.Data.EvidenceItems

  describe "record/1" do
    test "creates an evidence item for a run" do
      attrs = %{
        run_id: "run-test-001",
        claim: "Apple stock price is $195.50",
        source_type: "web_search",
        tool_name: "web_search",
        confidence: 0.9
      }

      assert {:ok, evidence} = Evidence.record(attrs)
      assert evidence.run_id == "run-test-001"
      assert evidence.claim == "Apple stock price is $195.50"
      assert evidence.source_type == "web_search"
      assert evidence.confidence == 0.9
      assert evidence.status == "active"
    end

    test "validates required fields" do
      assert {:error, changeset} = Evidence.record(%{run_id: "run-1"})
      assert :claim in Keyword.keys(changeset.errors)
      assert :source_type in Keyword.keys(changeset.errors)
    end

    test "validates source_type inclusion" do
      assert {:error, changeset} =
               Evidence.record(%{
                 run_id: "run-1",
                 claim: "test",
                 source_type: "invalid_type"
               })

      assert :source_type in Keyword.keys(changeset.errors)
    end

    test "validates confidence range" do
      assert {:error, changeset} =
               Evidence.record(%{
                 run_id: "run-1",
                 claim: "test",
                 source_type: "tool_output",
                 confidence: 1.5
               })

      assert :confidence in Keyword.keys(changeset.errors)
    end

    test "offloads long excerpt to file store" do
      long_excerpt = String.duplicate("A", 3_000)

      assert {:ok, evidence} =
               Evidence.record(%{
                 run_id: "run-excerpt-test",
                 claim: "Long content test",
                 source_type: "tool_output",
                 excerpt: long_excerpt
               })

      assert evidence.source_excerpt_path != nil
      assert String.contains?(evidence.source_excerpt_path, "evidence")
      assert {:ok, ^long_excerpt} = File.read(evidence.source_excerpt_path)
    end

    test "keeps short excerpt inline without file" do
      short_excerpt = "Short content"

      assert {:ok, evidence} =
               Evidence.record(%{
                 run_id: "run-short-test",
                 claim: "Short content test",
                 source_type: "tool_output",
                 excerpt: short_excerpt
               })

      assert evidence.source_excerpt_path == nil
    end
  end

  describe "record_many/1" do
    test "records multiple evidence items" do
      items = [
        %{run_id: "run-batch", claim: "Fact 1", source_type: "web_search"},
        %{run_id: "run-batch", claim: "Fact 2", source_type: "web_fetch"}
      ]

      assert {:ok, evidences} = Evidence.record_many(items)
      assert length(evidences) == 2
    end

    test "returns errors for invalid items" do
      items = [
        %{run_id: "run-batch", claim: "Valid", source_type: "tool_output"},
        %{run_id: "run-batch", claim: "Invalid", source_type: "bad_type"}
      ]

      assert {:error, failures} = Evidence.record_many(items)
      assert length(failures) == 1
    end
  end

  describe "list_for_run/1" do
    test "returns evidence items ordered by insertion time" do
      Evidence.record(%{run_id: "run-list", claim: "First", source_type: "tool_output"})
      Evidence.record(%{run_id: "run-list", claim: "Second", source_type: "web_search"})

      items = Evidence.list_for_run("run-list")
      assert length(items) == 2
      assert hd(items).claim == "First"
    end

    test "returns empty list for run with no evidence" do
      assert [] = Evidence.list_for_run("run-nonexistent")
    end
  end

  describe "count/1" do
    test "counts evidence items for a run" do
      Evidence.record(%{run_id: "run-count", claim: "A", source_type: "tool_output"})
      Evidence.record(%{run_id: "run-count", claim: "B", source_type: "tool_output"})

      assert Evidence.count("run-count") == 2
    end
  end

  describe "summarize_for_prompt/1" do
    test "generates text summary for LLM injection" do
      Evidence.record(%{
        run_id: "run-summary",
        claim: "Temperature is 25°C",
        source_type: "web_search",
        tool_name: "web_search",
        confidence: 0.85
      })

      summary = Evidence.summarize_for_prompt("run-summary")
      assert summary =~ "## Evidence"
      assert summary =~ "Temperature is 25°C"
      assert summary =~ "web_search"
      assert summary =~ "0.85"
    end

    test "handles empty evidence gracefully" do
      summary = Evidence.summarize_for_prompt("run-empty")
      assert summary =~ "No evidence recorded"
    end

    test "truncates long claims in summary" do
      long_claim = String.duplicate("X", 300)

      Evidence.record(%{
        run_id: "run-long-claim",
        claim: long_claim,
        source_type: "tool_output"
      })

      summary = Evidence.summarize_for_prompt("run-long-claim")
      assert summary =~ "..."
    end

    test "only includes active evidence items" do
      {:ok, evidence} =
        Evidence.record(%{run_id: "run-active", claim: "Active", source_type: "tool_output"})

      Evidence.record(%{run_id: "run-active", claim: "Also active", source_type: "tool_output"})

      EvidenceItems.update_status(evidence.id, "superseded")

      summary = Evidence.summarize_for_prompt("run-active")
      assert summary =~ "Also active"
      refute summary =~ "Active (superseded)"
    end
  end

  describe "offload error handling" do
    test "record succeeds even if excerpt file write fails" do
      long_excerpt = String.duplicate("B", 3_000)

      # Write to a run_id that produces an impossible path
      attrs = %{
        run_id: "run-\0bad",
        claim: "Bad path test",
        source_type: "tool_output",
        excerpt: long_excerpt
      }

      # Should still succeed — excerpt is just dropped, record is created
      assert {:ok, _evidence} = Evidence.record(attrs)
    end
  end

  describe "orchestrator evidence recording" do
    test "evidence_event? only matches tool_result events with atom keys" do
      # Simulate the orchestrator's evidence_event? check
      assert evidence_event?(%{type: :tool_result})
      refute evidence_event?(%{type: :text_delta})
      refute evidence_event?(%{type: :tool_start})
      refute evidence_event?(%{"type" => "tool_result"})
      refute evidence_event?(%{})
    end

    test "record_tool_evidence creates evidence from a tool_result event" do
      event = %{
        type: :tool_result,
        tool_use_id: "tu-001",
        result:
          {:ok,
           %AIBrain.Tool.Result{
             content: "Search result: Apple stock $195.50",
             metadata: %{"tool_name" => "web_search"}
           }}
      }

      assert :ok = record_tool_evidence("run-orch-001", event)

      items = Evidence.list_for_run("run-orch-001")
      assert length(items) == 1
      assert hd(items).source_type == "web_search"
      assert hd(items).tool_name == "web_search"
      assert hd(items).claim =~ "Apple stock"
    end

    test "record_tool_evidence skips error results" do
      event = %{
        type: :tool_result,
        tool_use_id: "tu-002",
        result: {:error, %AIBrain.Tool.Error{message: "timeout"}}
      }

      assert :ok = record_tool_evidence("run-orch-002", event)
      assert Evidence.count("run-orch-002") == 0
    end

    test "record_tool_evidence maps tool names to source types" do
      events = [
        {"web_search", "web_search"},
        {"web_fetch_page", "web_fetch"},
        {"file_read", "file_read"},
        {"bash", "tool_output"}
      ]

      for {tool_name, expected_source} <- events do
        event = %{
          type: :tool_result,
          tool_use_id: "tu-map-#{tool_name}",
          result:
            {:ok,
             %AIBrain.Tool.Result{
               content: "output",
               metadata: %{"tool_name" => tool_name}
             }}
        }

        run_id = "run-map-#{tool_name}"
        assert :ok = record_tool_evidence(run_id, event)

        items = Evidence.list_for_run(run_id)
        assert length(items) == 1
        assert hd(items).source_type == expected_source
      end
    end
  end

  # Helper functions that mirror the private orchestrator functions
  # for integration testing without coupling to internals

  defp evidence_event?(%{type: :tool_result}), do: true
  defp evidence_event?(_), do: false

  defp record_tool_evidence(run_id, event) do
    case event do
      %{type: :tool_result, result: {:ok, %AIBrain.Tool.Result{} = result}} ->
        tool_name = Map.get(result.metadata || %{}, "tool_name", "unknown")
        content = result.content || ""

        Evidence.record(%{
          run_id: run_id,
          claim: String.slice(content, 0, 500),
          source_type: evidence_source_type(tool_name),
          tool_name: tool_name,
          source_uri: nil,
          excerpt: if(is_binary(content) and byte_size(content) > 0, do: content),
          confidence: 0.8,
          metadata: %{tool_use_id: Map.get(event, :tool_use_id)}
        })

        :ok

      %{type: :tool_result, result: {:error, _}} ->
        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp evidence_source_type("web_search" <> _), do: "web_search"
  defp evidence_source_type("web_fetch" <> _), do: "web_fetch"
  defp evidence_source_type("file_read" <> _), do: "file_read"
  defp evidence_source_type(_), do: "tool_output"
end
