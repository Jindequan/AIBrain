defmodule AIBrain.Session.HistoryTest do
  use ExUnit.Case, async: true

  alias AIBrain.Message
  alias AIBrain.Session.History

  test "already loaded history counts assistant turns for Message structs" do
    result =
      History.load(
        "session-1",
        [
          Message.from_json(%{"role" => "user", "content" => "hello"}),
          Message.from_json(%{"role" => "assistant", "content" => "hi"}),
          Message.from_json(%{"role" => "assistant", "content" => "again"})
        ],
        _history_loaded: true
      )

    assert result.seed_turn == 2
    assert result.source == :log
  end
end
