defmodule AIBrain.Data.RunStep do
  @moduledoc """
  A small, auditable runtime step.

  Large LLM messages, tool output, and generated files live on disk. This schema
  stores phase/status, short summaries, and file paths only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @phases ~w(context analysis correction planning executing waiting observing verifying reporting completed failed cancelled)
  @statuses ~w(pending running waiting completed failed skipped cancelled)
  @kinds ~w(system llm reasoning review plan tool policy memory approval user_input external_event child_run schedule report verification)

  @derive {Jason.Encoder,
           only: [
             :id,
             :run_id,
             :step_index,
             :phase,
             :status,
             :kind,
             :title,
             :summary,
             :input_path,
             :output_path,
             :error,
             :metadata,
             :started_at,
             :completed_at,
             :inserted_at,
             :updated_at
           ]}

  schema "run_steps" do
    field(:run_id, :string)
    field(:step_index, :integer)
    field(:phase, :string)
    field(:status, :string, default: "pending")
    field(:kind, :string)
    field(:title, :string)
    field(:summary, :string)
    field(:input_path, :string)
    field(:output_path, :string)
    field(:error, :string)
    field(:metadata, :map, default: %{})
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    timestamps()
  end

  def phases, do: @phases
  def statuses, do: @statuses
  def kinds, do: @kinds

  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :id,
      :run_id,
      :step_index,
      :phase,
      :status,
      :kind,
      :title,
      :summary,
      :input_path,
      :output_path,
      :error,
      :metadata,
      :started_at,
      :completed_at
    ])
    |> SchemaHelpers.put_generated_id()
    |> put_default_started_at()
    |> validate_required([:id, :run_id, :step_index, :phase, :status])
    |> validate_inclusion(:phase, @phases)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:kind, @kinds)
  end

  defp put_default_started_at(changeset) do
    case get_field(changeset, :started_at) do
      nil -> put_change(changeset, :started_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end
end
