defmodule AIBrain.Data.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :parent_id,
             :title,
             :description,
             :status,
             :priority,
             :metadata,
             :workspace_path,
             :inserted_at,
             :updated_at
           ]}

  schema "goals" do
    field(:title, :string)
    field(:description, :string)
    field(:status, :string, default: "active")
    field(:priority, :integer, default: 3)
    field(:metadata, :map, default: %{})
    field(:workspace_path, :string)

    belongs_to(:parent, __MODULE__)
    has_many(:children, __MODULE__, foreign_key: :parent_id)

    timestamps()
  end

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [
      :id,
      :parent_id,
      :title,
      :description,
      :status,
      :priority,
      :metadata,
      :workspace_path
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :title])
    |> validate_inclusion(:status, ["active", "paused", "completed", "archived"])
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> foreign_key_constraint(:parent_id)
  end
end
