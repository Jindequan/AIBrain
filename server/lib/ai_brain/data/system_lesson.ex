defmodule AIBrain.Data.SystemLesson do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}

  @target_types ~w(proxy tool_selection analysis intent plan memory)

  @derive {Jason.Encoder,
           only: [
             :id,
             :target_type,
             :lesson,
             :source_count,
             :version,
             :active,
             :changelog,
             :inserted_at,
             :updated_at
           ]}

  schema "system_lessons" do
    field(:target_type, :string)
    field(:lesson, :string)
    field(:source_count, :integer, default: 1)
    field(:version, :integer, default: 1)
    field(:active, :boolean, default: true)
    field(:changelog, :string)

    timestamps()
  end

  def changeset(lesson, attrs) do
    lesson
    |> cast(attrs, [:id, :target_type, :lesson, :source_count, :version, :active, :changelog])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :target_type, :lesson])
    |> validate_inclusion(:target_type, @target_types)
  end
end
