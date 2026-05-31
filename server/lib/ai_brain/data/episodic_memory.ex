defmodule AIBrain.Data.EpisodicMemory do
  use Ecto.Schema
  import Ecto.Changeset
  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :goal_id,
             :task_id,
             :run_id,
             :event_start_id,
             :event_end_id,
             :period_start,
             :period_end,
             :narrative,
             :objective,
             :approach,
             :key_decisions,
             :success_score,
             :lessons,
             :difficulties,
             :tool_usage_summary,
             :tags,
             :importance_score,
             :inserted_at,
             :updated_at
           ]}

  schema "episodic_memories" do
    field(:goal_id, :string)
    field(:task_id, :string)
    field(:run_id, :string)
    field(:event_start_id, :string)
    field(:event_end_id, :string)
    field(:period_start, :utc_datetime)
    field(:period_end, :utc_datetime)
    field(:narrative, :string)
    field(:objective, :string)
    field(:approach, :string)
    field(:key_decisions, :map, default: %{})
    field(:success_score, :float, default: 0.0)
    field(:lessons, {:array, :string}, default: [])
    field(:difficulties, :map, default: %{})
    field(:tool_usage_summary, :map, default: %{})
    field(:tags, {:array, :string}, default: [])
    field(:importance_score, :float, default: 0.0)

    timestamps()
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :id,
      :goal_id,
      :task_id,
      :run_id,
      :event_start_id,
      :event_end_id,
      :period_start,
      :period_end,
      :narrative,
      :objective,
      :approach,
      :key_decisions,
      :success_score,
      :lessons,
      :difficulties,
      :tool_usage_summary,
      :tags,
      :importance_score
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :narrative])
  end
end
