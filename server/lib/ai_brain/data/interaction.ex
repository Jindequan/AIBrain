defmodule AIBrain.Data.Interaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}

  @types ~w(approval confirm select text_input form shell_exec)
  @statuses ~w(pending proxy_running need_manual resolved escalated expired cancelled)

  @derive {Jason.Encoder,
           only: [
             :id,
             :type,
             :status,
             :schema_data,
             :context,
             :result,
             :proxy_trail,
             :resolved_by,
             :resume_token,
             :prompt_versions,
             :expires_at,
             :resolved_at,
             :inserted_at,
             :updated_at
           ]}

  schema "interactions" do
    field(:type, :string)
    field(:status, :string, default: "pending")
    field(:schema_data, :map, default: %{})
    field(:context, :map, default: %{})
    field(:result, :map, default: %{})
    field(:proxy_trail, {:array, :map}, default: [])
    field(:resolved_by, :string)
    field(:expires_at, :string)
    field(:resolved_at, :string)
    field(:resume_token, :string)
    field(:prompt_versions, :map, default: %{})

    timestamps()
  end

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [
      :id,
      :type,
      :status,
      :schema_data,
      :context,
      :result,
      :proxy_trail,
      :resolved_by,
      :resume_token,
      :prompt_versions,
      :expires_at,
      :resolved_at
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :type])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
  end
end
