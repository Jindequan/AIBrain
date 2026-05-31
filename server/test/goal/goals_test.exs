defmodule AIBrain.Goal.GoalsTest do
  use AIBrain.DataCase
  alias AIBrain.Data.Goals

  describe "create/1" do
    test "creates goal with valid attrs" do
      attrs = %{
        title: "Launch MVP",
        description: "Get product to market"
      }

      assert {:ok, goal} = Goals.create(attrs)
      assert goal.title == "Launch MVP"
      assert goal.description == "Get product to market"
      assert goal.status == "active"
      assert goal.priority == 3
      assert is_binary(goal.id)
    end

    test "creates goal with parent" do
      {:ok, parent} = Goals.create(%{title: "Parent goal"})

      attrs = %{
        title: "Child goal",
        parent_id: parent.id
      }

      assert {:ok, child} = Goals.create(attrs)
      assert child.parent_id == parent.id
    end

    test "returns error for invalid attrs" do
      attrs = %{}

      assert {:error, _reason} = Goals.create(attrs)
    end
  end

  describe "list/1" do
    setup do
      {:ok, goal1} = Goals.create(%{title: "Goal 1", status: "active"})
      {:ok, goal2} = Goals.create(%{title: "Goal 2", status: "completed"})
      {:ok, goal3} = Goals.create(%{title: "Goal 3", parent_id: goal1.id})

      %{goal1: goal1, goal2: goal2, goal3: goal3}
    end

    test "lists all goals" do
      assert {:ok, goals} = Goals.list()
      assert length(goals) == 3
    end

    test "filters by status" do
      assert {:ok, goals} = Goals.list(status: "active")
      assert length(goals) == 2
    end

    test "filters by parent_id" do
      assert {:ok, goals} = Goals.list(parent_id: nil)
      assert length(goals) == 2
    end
  end

  describe "get/1" do
    test "returns goal by id" do
      {:ok, goal} = Goals.create(%{title: "Test goal"})

      assert {:ok, found} = Goals.get(goal.id)
      assert found.id == goal.id
      assert found.title == "Test goal"
    end

    test "returns error for not found" do
      assert {:error, :not_found} = Goals.get("nonexistent")
    end
  end

  describe "update/2" do
    test "updates goal" do
      {:ok, goal} = Goals.create(%{title: "Old title"})

      assert {:ok, updated} = Goals.update(goal.id, %{title: "New title"})
      assert updated.title == "New title"
    end

    test "returns error for not found" do
      assert {:error, :not_found} = Goals.update("nonexistent", %{title: "New"})
    end
  end

  describe "delete/1" do
    test "deletes goal" do
      {:ok, goal} = Goals.create(%{title: "Delete me"})

      assert :ok = Goals.delete(goal.id)
      assert {:error, :not_found} = Goals.get(goal.id)
    end

    test "returns error for not found" do
      assert {:error, :not_found} = Goals.delete("nonexistent")
    end
  end
end
