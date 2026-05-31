defmodule AIBrain.Data.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :parent_id,
             :goal_id,
             :title,
             :description,
             :status,
             :priority,
             :required_skills,
             :metadata,
             :depends_on,
             :output,
             :run_id,
             :inserted_at,
             :updated_at
           ]}

  schema "tasks" do
    field(:title, :string)
    field(:description, :string)
    field(:status, :string, default: "pending")
    field(:priority, :integer, default: 3)
    field(:required_skills, {:array, :string}, default: [])
    field(:metadata, :map, default: %{})
    field(:depends_on, {:array, :string}, default: [])
    field(:output, :string)
    field(:run_id, :string)

    belongs_to(:parent, __MODULE__)
    has_many(:children, __MODULE__, foreign_key: :parent_id)
    belongs_to(:goal, AIBrain.Data.Goal)

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :id,
      :parent_id,
      :goal_id,
      :title,
      :description,
      :status,
      :priority,
      :required_skills,
      :metadata,
      :depends_on,
      :output,
      :run_id
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :title])
    |> validate_inclusion(:status, [
      "pending",
      "assigned",
      "running",
      "in_progress",
      "completed",
      "failed",
      "cancelled"
    ])
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:goal_id)
  end
end
