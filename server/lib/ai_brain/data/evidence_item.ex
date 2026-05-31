defmodule AIBrain.Data.EvidenceItem do
  @moduledoc """
  A piece of evidence backing a factual claim during a run.

  Long source excerpts are stored in FileStore; this schema holds only the
  file path. Database rows keep claim text, source metadata, and confidence.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @source_types ~w(tool_output web_search web_fetch file_read llm_inference user_input knowledge)
  @statuses ~w(active disputed superseded unknown unverified)

  @derive {Jason.Encoder,
           only: [
             :id,
             :run_id,
             :step_id,
             :claim,
             :source_type,
             :source_uri,
             :source_title,
             :source_excerpt_path,
             :tool_name,
             :confidence,
             :status,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  schema "evidence_items" do
    field(:run_id, :string)
    field(:step_id, :string)
    field(:claim, :string)
    field(:source_type, :string)
    field(:source_uri, :string)
    field(:source_title, :string)
    field(:source_excerpt_path, :string)
    field(:tool_name, :string)
    field(:confidence, :float, default: 0.5)
    field(:status, :string, default: "active")
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def source_types, do: @source_types
  def statuses, do: @statuses

  def changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [
      :id,
      :run_id,
      :step_id,
      :claim,
      :source_type,
      :source_uri,
      :source_title,
      :source_excerpt_path,
      :tool_name,
      :confidence,
      :status,
      :metadata
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :run_id, :claim, :source_type])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
