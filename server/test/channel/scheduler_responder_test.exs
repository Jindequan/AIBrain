defmodule AIBrain.Channel.Responders.SchedulerResponderTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Responders.SchedulerResponder

  describe "build_status/1" do
    test "renders diagnostics summary" do
      diag = %{
        counts: %{active: 2, paused: 1, fired: 3, cancelled: 0, total: 6},
        upcoming: []
      }

      reply = SchedulerResponder.build_status(diag)
      assert reply.role == "assistant"
      assert reply.metadata.surface == :scheduler_status
      assert reply.content =~ "Active: 2"
      assert reply.content =~ "Paused: 1"
    end

    test "renders upcoming items" do
      upcoming = [
        %{
          id: "sched-1",
          type: :one_shot,
          next_fire_at: ~U[2026-05-01 09:00:00Z]
        }
      ]

      diag = %{
        counts: %{active: 1, paused: 0, fired: 0, cancelled: 0, total: 1},
        upcoming: upcoming
      }

      reply = SchedulerResponder.build_status(diag)
      assert reply.content =~ "sched-1"
    end
  end

  describe "build_item_created/1" do
    test "renders creation confirmation" do
      item = %{
        id: "sched-42",
        type: :one_shot,
        next_fire_at: ~U[2026-05-01 09:00:00Z]
      }

      reply = SchedulerResponder.build_item_created(item)
      assert reply.content =~ "sched-42"
      assert reply.metadata.item_id == "sched-42"
    end
  end
end
