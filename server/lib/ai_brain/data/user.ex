defmodule AIBrain.Data.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :bio,
             :role,
             :active,
             :profile,
             :preferences,
             :inserted_at,
             :updated_at
           ]}

  schema "users" do
    field(:name, :string)
    field(:bio, :string)
    field(:role, :string, default: "user")
    field(:active, :boolean, default: false)
    field(:profile, :string)
    field(:preferences, AIBrain.Data.JSONMap, default: %{})

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :name, :bio, :role, :active, :profile, :preferences])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :name])
  end
end
