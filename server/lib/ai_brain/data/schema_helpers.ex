defmodule AIBrain.Data.SchemaHelpers do
  @moduledoc false

  def put_generated_id(changeset) do
    case Ecto.Changeset.get_field(changeset, :id) do
      nil -> Ecto.Changeset.put_change(changeset, :id, Ecto.UUID.generate())
      "" -> Ecto.Changeset.put_change(changeset, :id, Ecto.UUID.generate())
      _id -> changeset
    end
  end
end
