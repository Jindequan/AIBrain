defmodule AIBrain.Web.MemoryHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AIBrain.Data.{EpisodicMemories, EpisodicMemory, Goals}
  alias AIBrain.Repo
  alias AIBrain.Web.Handlers.MemoryHandler
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Repo.delete_all(EpisodicMemory)
    :ok
  end

  test "lists episodic memories scoped by goal_id" do
    {:ok, goal} = Goals.create(%{title: "Memory goal"})
    {:ok, other_goal} = Goals.create(%{title: "Other memory goal"})

    {:ok, memory} =
      EpisodicMemories.create(%{
        goal_id: goal.id,
        run_id: "run-episodic-1",
        narrative: "The weekly review produced better next actions.",
        objective: "Improve cadence",
        lessons: ["Review weekly"],
        importance_score: 0.7
      })

    {:ok, _other} =
      EpisodicMemories.create(%{
        goal_id: other_goal.id,
        narrative: "Unrelated memory"
      })

    conn =
      MemoryHandler.handle_list(
        conn(:get, "/api/v1/memory"),
        %{"type" => "episodic", "goal_id" => goal.id}
      )

    assert conn.status == 200
    assert [%{"id" => memory_id} = item] = Jason.decode!(conn.resp_body)["entries"]
    assert memory_id == memory.id
    assert item["type"] == "episodic"
    assert item["run_id"] == "run-episodic-1"
    assert item["lessons"] == ["Review weekly"]
  end

  test "lists recent episodic memories with a bounded limit" do
    {:ok, goal} = Goals.create(%{title: "Recent memory goal"})

    for index <- 1..3 do
      {:ok, _memory} =
        EpisodicMemories.create(%{
          goal_id: goal.id,
          narrative: "Memory #{index}"
        })
    end

    conn =
      MemoryHandler.handle_list(
        conn(:get, "/api/v1/memory"),
        %{"type" => "episodic", "limit" => "2"}
      )

    assert conn.status == 200
    assert length(Jason.decode!(conn.resp_body)["entries"]) == 2
  end
end
