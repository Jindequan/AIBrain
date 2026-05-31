defmodule AIBrain.Data.Schedule do
  @moduledoc """
  Ecto schema for the unified `schedules` table.

  Replaces both legacy raw SQLite scheduled tasks and automation rules with a single schedule record
  that stores trigger configuration, action configuration, and execution state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :trigger_type,
             :trigger_config,
             :action_type,
             :action_config,
             :status,
             :priority,
             :next_fire_at,
             :last_fired_at,
             :last_result,
             :inserted_at,
             :updated_at
           ]}

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "schedules" do
    field(:name, :string)
    field(:trigger_type, :string)
    field(:trigger_config, :map, default: %{})
    field(:action_type, :string)
    field(:action_config, :map, default: %{})
    field(:status, :string, default: "active")
    field(:priority, :integer, default: 3)
    field(:next_fire_at, :utc_datetime)
    field(:last_fired_at, :utc_datetime)
    field(:last_result, :string)

    timestamps()
  end

  @doc "Valid trigger types"
  @spec trigger_types :: [String.t()]
  def trigger_types, do: ["cron", "time", "event", "condition", "manual"]

  @doc "Valid action types"
  @spec action_types :: [String.t()]
  def action_types, do: ["create_task", "send_notification", "run_query"]

  @doc "Valid statuses"
  @spec statuses :: [String.t()]
  def statuses, do: ["active", "paused", "completed", "cancelled"]

  @doc "Build a changeset for creating or updating a schedule."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :id,
      :name,
      :trigger_type,
      :trigger_config,
      :action_type,
      :action_config,
      :status,
      :priority,
      :next_fire_at,
      :last_fired_at,
      :last_result
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :name, :trigger_type, :action_type])
    |> validate_inclusion(:trigger_type, trigger_types())
    |> validate_inclusion(:action_type, action_types())
    |> validate_inclusion(:status, statuses())
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
