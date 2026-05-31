defmodule AIBrain.Repo.TaskSchemaTest do
  use AIBrain.DataCase
  alias AIBrain.Data.Task, as: Schema
  import Ecto.Changeset

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        id: "task-1",
        title: "Design database"
      }

      changeset = Schema.changeset(%Schema{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :id) == "task-1"
      assert get_change(changeset, :title) == "Design database"
    end

    test "allows optional goal_id" do
      attrs = %{
        id: "task-1",
        title: "Design database",
        goal_id: "goal-1"
      }

      changeset = Schema.changeset(%Schema{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :goal_id) == "goal-1"
    end

    test "validates without goal_id" do
      attrs = %{
        id: "task-1",
        title: "Standalone task"
      }

      changeset = Schema.changeset(%Schema{}, attrs)

      assert changeset.valid?
    end

    test "allows parent_id for subtasks" do
      attrs = %{
        id: "subtask-1",
        title: "Subtask",
        parent_id: "task-1"
      }

      changeset = Schema.changeset(%Schema{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :parent_id) == "task-1"
    end

    test "accepts depends_on and output fields" do
      attrs = %{
        id: "task-1",
        title: "Test Task",
        goal_id: "goal-1",
        depends_on: ["task-1", "task-2"],
        output: "done"
      }

      changeset = Schema.changeset(%Schema{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :depends_on) == ["task-1", "task-2"]
      assert get_change(changeset, :output) == "done"
    end
  end
end
