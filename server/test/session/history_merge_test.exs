defmodule AIBrain.Session.HistoryMergeTest do
  use ExUnit.Case, async: true

  alias AIBrain.Message
  alias AIBrain.Session.HistoryMerge

  test "does not duplicate a current user message already persisted at the end of history" do
    history = [
      Message.from_json(%{"role" => "user", "content" => "first"}),
      Message.from_json(%{"role" => "assistant", "content" => "answer"}),
      Message.from_json(%{"role" => "user", "content" => "follow up"})
    ]

    merged = HistoryMerge.merge(history, [%{role: "user", content: "follow up"}])

    assert length(merged) == 3
    assert Enum.map(merged, &role/1) == ["user", "assistant", "user"]
  end

  test "keeps genuinely new messages" do
    history = [
      Message.from_json(%{"role" => "user", "content" => "first"}),
      Message.from_json(%{"role" => "assistant", "content" => "answer"})
    ]

    merged = HistoryMerge.merge(history, [%{role: "user", content: "follow up"}])

    assert length(merged) == 3
    assert List.last(merged).content == "follow up"
  end

  test "deduplicates overlapping multi-message tails" do
    history = [
      Message.from_json(%{"role" => "user", "content" => "first"}),
      Message.from_json(%{"role" => "assistant", "content" => "answer"}),
      Message.from_json(%{"role" => "user", "content" => "follow up"})
    ]

    merged =
      HistoryMerge.merge(history, [
        %{role: "assistant", content: "answer"},
        %{role: "user", content: "follow up"},
        %{role: "assistant", content: "new answer"}
      ])

    assert Enum.map(merged, &role/1) == ["user", "assistant", "user", "assistant"]
  end

  test "deduplicates full history prefix when caller sends entire transcript plus new message" do
    history = [
      Message.from_json(%{"role" => "user", "content" => "first"}),
      Message.from_json(%{"role" => "assistant", "content" => "answer"})
    ]

    merged =
      HistoryMerge.merge(history, [
        %{role: "user", content: "first"},
        %{role: "assistant", content: "answer"},
        %{role: "user", content: "follow up"}
      ])

    assert Enum.map(merged, &role/1) == ["user", "assistant", "user"]
    assert List.last(merged).content == "follow up"
  end

  defp role(%Message{role: role}), do: role
  defp role(%{role: role}), do: role
end
