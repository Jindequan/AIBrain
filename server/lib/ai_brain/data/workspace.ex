defmodule AIBrain.Data.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :name, :path, :metadata, :inserted_at, :updated_at]}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "workspaces" do
    field(:name, :string)
    field(:path, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:id, :name, :path, :metadata])
    |> validate_required([:id, :name, :path])
    |> unique_constraint(:path)
  end
end
