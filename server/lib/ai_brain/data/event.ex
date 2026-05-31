defmodule AIBrain.Data.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :correlation_id,
             :event_type,
             :source,
             :channel_type,
             :payload,
             :metadata,
             :session_id,
             :goal_id,
             :task_id,
             :run_id,
             :importance,
             :token_count,
             :snapshot_id,
             :inserted_at,
             :updated_at
           ]}

  schema "events" do
    field(:correlation_id, :string)
    field(:event_type, :string)
    field(:source, :string)
    field(:channel_type, :string)
    field(:payload, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:session_id, :string)
    field(:goal_id, :string)
    field(:task_id, :string)
    field(:run_id, :string)
    field(:importance, :float, default: 0.5)
    field(:token_count, :integer, default: 0)
    field(:snapshot_id, :string)

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :correlation_id,
      :event_type,
      :source,
      :channel_type,
      :payload,
      :metadata,
      :session_id,
      :goal_id,
      :task_id,
      :run_id,
      :importance,
      :token_count,
      :snapshot_id
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :correlation_id, :event_type, :source, :importance, :token_count])
  end
end
