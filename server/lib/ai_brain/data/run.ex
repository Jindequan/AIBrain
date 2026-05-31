defmodule AIBrain.Data.Run do
  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @statuses ~w(pending running waiting_approval waiting_assistant completed completed_with_warnings failed cancelled)
  @source_types ~w(chat session task goal schedule manual webhook system)

  @derive {Jason.Encoder,
           only: [
             :id,
             :source_type,
             :source_id,
             :status,
             :input,
             :output,
             :output_summary,
             :error,
             :model,
             :mode,
             :phase,
             :objective,
             :autonomy_level,
             :workspace_path,
             :messages_path,
             :output_path,
             :parent_run_id,
             :title,
             :metadata,
             :deliverables,
             :started_at,
             :completed_at,
             :inserted_at,
             :updated_at
           ]}

  schema "runs" do
    field(:source_type, :string)
    field(:source_id, :string)
    field(:status, :string, default: "pending")
    field(:input, :map, default: %{})
    field(:output, :string)
    field(:output_summary, :string)
    field(:error, :string)
    field(:model, :string)
    field(:mode, :string)
    field(:phase, :string)
    field(:objective, :string)
    field(:autonomy_level, :integer, default: 0)
    field(:workspace_path, :string)
    field(:messages_path, :string)
    field(:output_path, :string)
    field(:parent_run_id, :string)
    field(:title, :string)
    field(:metadata, :map, default: %{})
    field(:deliverables, {:array, :map}, default: [])
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    timestamps()
  end

  def statuses, do: @statuses
  def source_types, do: @source_types

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :id,
      :source_type,
      :source_id,
      :status,
      :input,
      :output,
      :output_summary,
      :error,
      :model,
      :mode,
      :phase,
      :objective,
      :autonomy_level,
      :workspace_path,
      :messages_path,
      :output_path,
      :parent_run_id,
      :title,
      :metadata,
      :deliverables,
      :started_at,
      :completed_at
    ])
    |> SchemaHelpers.put_generated_id()
    |> put_default_started_at()
    |> validate_required([:id, :source_type, :status])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:status, @statuses)
  end

  defp put_default_started_at(changeset) do
    status = get_field(changeset, :status)

    case {get_field(changeset, :started_at), status} do
      {nil, status} when status != "pending" ->
        put_change(changeset, :started_at, DateTime.utc_now() |> DateTime.truncate(:second))

      _ ->
        changeset
    end
  end
end
