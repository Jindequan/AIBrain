defmodule AIBrain.Data.GoalsTest do
  use AIBrain.DataCase

  alias AIBrain.Data.Goals

  describe "update_status/2" do
    test "updates goal status" do
      {:ok, goal} = Goals.create(%{title: "Test", status: "active"})
      {:ok, updated} = Goals.update_status(goal.id, "completed")
      assert updated.status == "completed"
    end

    test "returns error for non-existent goal" do
      assert Goals.update_status("nonexistent", "completed") == {:error, :not_found}
    end
  end
end
