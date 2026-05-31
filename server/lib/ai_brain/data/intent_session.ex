defmodule AIBrain.Data.IntentSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @statuses ~w(classifying clarifying confirmed executing completed failed cancelled)

  @derive {Jason.Encoder,
           only: [
             :id,
             :session_id,
             :parent_intent_id,
             :run_id,
             :status,
             :intent_type,
             :intent_subtype,
             :parameters,
             :constraints,
             :confidence,
             :reasoning,
             :skill_id,
             :pending_questions,
             :user_responses,
             :resolved_at,
             :inserted_at,
             :updated_at
           ]}

  schema "intent_sessions" do
    field(:session_id, :string)
    field(:parent_intent_id, :string)
    field(:run_id, :string)
    field(:status, :string, default: "classifying")
    field(:intent_type, :string)
    field(:intent_subtype, :string)
    field(:parameters, :map, default: %{})
    field(:constraints, :map, default: %{})
    field(:confidence, :float, default: 0.0)
    field(:reasoning, :string)
    field(:skill_id, :string)
    field(:pending_questions, {:array, :map}, default: [])
    field(:user_responses, {:array, :map}, default: [])
    field(:resolved_at, :utc_datetime)

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(intent_session, attrs) do
    intent_session
    |> cast(attrs, [
      :id,
      :session_id,
      :parent_intent_id,
      :run_id,
      :status,
      :intent_type,
      :intent_subtype,
      :parameters,
      :constraints,
      :confidence,
      :reasoning,
      :skill_id,
      :pending_questions,
      :user_responses,
      :resolved_at
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :session_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
