defmodule AIBrain.Data.RunContextRef do
  @moduledoc """
  Normalized context references for a run.

  `runs.source_type/source_id` answers what triggered this run. This table
  answers what business context the run belongs to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @ref_types ~w(thread session goal task schedule workspace project user artifact)
  @roles ~w(primary related parent trigger dependency owner)

  @derive {Jason.Encoder,
           only: [
             :id,
             :run_id,
             :ref_type,
             :ref_id,
             :role,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  schema "run_context_refs" do
    field(:run_id, :string)
    field(:ref_type, :string)
    field(:ref_id, :string)
    field(:role, :string, default: "related")
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def ref_types, do: @ref_types
  def roles, do: @roles

  def changeset(ref, attrs) do
    ref
    |> cast(attrs, [:id, :run_id, :ref_type, :ref_id, :role, :metadata])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :run_id, :ref_type, :ref_id, :role])
    |> validate_inclusion(:ref_type, @ref_types)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:run_id, :ref_type, :ref_id, :role])
  end
end
