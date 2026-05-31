defmodule AIBrain.Data.NotificationQueueItem do
  @moduledoc """
  Ecto schema for the notification_queue table.

  Each row represents an outbound notification enqueued for reliable delivery
  to one of the configured gateway channels (telegram, websocket, desktop).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AIBrain.Data.SchemaHelpers

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  @derive {Jason.Encoder,
           only: [
             :id,
             :event_id,
             :channel,
             :status,
             :payload,
             :retry_count,
             :max_retries,
             :last_error,
             :scheduled_at,
             :delivered_at,
             :inserted_at,
             :updated_at
           ]}

  schema "notification_queue" do
    field(:event_id, :string)
    field(:channel, :string)
    field(:status, :string, default: "pending")
    field(:payload, :map)
    field(:retry_count, :integer, default: 0)
    field(:max_retries, :integer, default: 5)
    field(:last_error, :string)
    field(:scheduled_at, :utc_datetime)
    field(:delivered_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :id,
      :event_id,
      :channel,
      :status,
      :payload,
      :retry_count,
      :max_retries,
      :last_error,
      :scheduled_at,
      :delivered_at
    ])
    |> SchemaHelpers.put_generated_id()
    |> validate_required([:id, :event_id, :channel])
  end
end
