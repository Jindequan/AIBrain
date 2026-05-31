defmodule AIBrain.Data.UserPrompt do
  use Ecto.Schema
  import Ecto.Changeset
  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :category,
             :template,
             :variables,
             :is_active,
             :description,
             :inserted_at,
             :updated_at
           ]}

  schema "user_prompts" do
    field(:name, :string)
    field(:category, :string)
    field(:template, :string)
    field(:variables, :string)
    field(:is_active, :boolean, default: true)
    field(:description, :string)
    timestamps()
  end

  def changeset(user_prompt, attrs) do
    user_prompt
    |> cast(attrs, [
      :id,
      :name,
      :category,
      :template,
      :variables,
      :is_active,
      :description
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :name, :template])
    |> validate_inclusion(:category, ["business", "coding", "writing", "custom", nil])
  end
end
