defmodule AIBrain.Data.Feedback do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}

  @target_types ~w(proxy tool_selection analysis intent plan memory)
  @severities ~w(minor significant critical)
  @statuses ~w(pending accepted rejected applied)

  @derive {Jason.Encoder,
           only: [
             :id,
             :interaction_id,
             :target_type,
             :original_action,
             :original_reasoning,
             :user_correction,
             :expected_action,
             :context_snapshot,
             :severity,
             :status,
             :source,
             :inserted_at,
             :updated_at
           ]}

  schema "feedback" do
    field(:interaction_id, :string)
    field(:target_type, :string)
    field(:original_action, :string)
    field(:original_reasoning, :string)
    field(:user_correction, :string)
    field(:expected_action, :string)
    field(:context_snapshot, :map, default: %{})
    field(:severity, :string, default: "minor")
    field(:status, :string, default: "pending")
    field(:source, :string, default: "user")

    timestamps()
  end

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [
      :id,
      :interaction_id,
      :target_type,
      :original_action,
      :original_reasoning,
      :user_correction,
      :expected_action,
      :context_snapshot,
      :severity,
      :status,
      :source
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :target_type, :original_action])
    |> validate_inclusion(:target_type, @target_types)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:status, @statuses)
  end
end
