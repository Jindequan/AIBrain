defmodule AIBrain.Tool.ResultTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Result

  describe "head_tail/2 — overlap-safe head+tail split" do
    test "returns {:full, lines} when lines fit within head + tail" do
      lines = Enum.map(1..10, &Integer.to_string/1)
      assert {:full, ^lines} = Result.head_tail(lines, head: 20, tail: 20)
    end

    test "returns {:full, lines} with default opts when short" do
      lines = Enum.map(1..30, &Integer.to_string/1)
      assert {:full, ^lines} = Result.head_tail(lines)
    end

    test "returns {:split, head, tail, skipped} when lines exceed head + tail" do
      lines = Enum.map(1..100, &Integer.to_string/1)
      {:split, head, tail, skipped} = Result.head_tail(lines, head: 20, tail: 20)

      assert length(head) == 20
      assert length(tail) == 20
      assert skipped == 60
      assert List.first(head) == "1"
      assert List.last(tail) == "100"
    end

    test "no overlap: head last element < tail first element" do
      lines = Enum.map(1..50, &Integer.to_string/1)
      {:split, head, tail, _skipped} = Result.head_tail(lines, head: 20, tail: 20)

      {last_head, _} = Integer.parse(List.last(head))
      {first_tail, _} = Integer.parse(List.first(tail))
      assert last_head < first_tail
    end

    test "boundary case: exactly head + tail lines returns {:full, ...}" do
      lines = Enum.map(1..40, &Integer.to_string/1)
      assert {:full, ^lines} = Result.head_tail(lines, head: 20, tail: 20)
    end

    test "boundary case: head + tail + 1 lines returns {:split, ...}" do
      lines = Enum.map(1..41, &Integer.to_string/1)
      assert {:split, _, _, 1} = Result.head_tail(lines, head: 20, tail: 20)
    end
  end
end
