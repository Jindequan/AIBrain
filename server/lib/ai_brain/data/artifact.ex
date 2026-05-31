defmodule AIBrain.Data.Artifact do
  @moduledoc """
  A deliverable produced by an AI task or conversation run.

  Artifacts are NOT file-level operation logs. They are task-level deliverables —
  the things a user cares about as output: a project directory, a script, a generated
  image, a document, a URL, or a text summary.

  Each artifact is linked to the run that produced it. Since runs are already linked
  to sessions (source_type: "session") or tasks (source_type: "task"), artifacts
  can be traced back to their originating context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :run_id,
             :kind,
             :title,
             :description,
             :uri,
             :content,
             :size,
             :mime_type,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  alias AIBrain.Data.SchemaHelpers

  @valid_kinds ~w(directory file image url note document code)

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "artifacts" do
    field(:run_id, :string)
    field(:kind, :string)
    field(:title, :string)
    field(:description, :string)
    field(:uri, :string)
    field(:content, :string)
    field(:size, :integer)
    field(:mime_type, :string)
    field(:metadata, :map, default: %{})
    timestamps()
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :id,
      :run_id,
      :kind,
      :title,
      :description,
      :uri,
      :content,
      :size,
      :mime_type,
      :metadata
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :kind, :title])
    |> validate_inclusion(:kind, @valid_kinds)
  end

  @doc "List of valid artifact kinds for external use."
  def valid_kinds, do: @valid_kinds
end
