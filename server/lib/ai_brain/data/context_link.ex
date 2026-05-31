defmodule AIBrain.Data.ContextLink do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :owner_type,
             :owner_id,
             :target_type,
             :target_id,
             :uri,
             :title,
             :summary,
             :relevance,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  schema "context_links" do
    field(:owner_type, :string)
    field(:owner_id, :string)
    field(:target_type, :string)
    field(:target_id, :string)
    field(:context_type, :string)
    field(:uri, :string)
    field(:title, :string)
    field(:summary, :string)
    field(:relevance, :float, default: 0.5)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :id,
      :owner_type,
      :owner_id,
      :target_type,
      :target_id,
      :context_type,
      :uri,
      :title,
      :summary,
      :relevance,
      :metadata
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :owner_type, :owner_id, :target_type])
    |> validate_inclusion(:owner_type, ["run"])
    |> validate_inclusion(:target_type, [
      "knowledge_entry",
      "artifact",
      "session",
      "file",
      "url",
      "person",
      "freeform"
    ])
    |> validate_number(:relevance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
