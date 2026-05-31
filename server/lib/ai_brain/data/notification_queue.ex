defmodule AIBrain.Data.NotificationQueue do
  @moduledoc """
  CRUD operations for the notification_queue table.

  Provides the persistence layer used by DispatchQueue for reliable
  outbound notification delivery with retry and backoff.
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.NotificationQueueItem

  @doc """
  Create a new notification queue entry.
  """
  def create(attrs) do
    %NotificationQueueItem{}
    |> NotificationQueueItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get pending notifications ordered by scheduled_at, limited to `limit`.
  """
  def get_pending(limit \\ 10) do
    NotificationQueueItem
    |> where([n], n.status == "pending")
    |> order_by([n], asc: n.scheduled_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Mark a notification as currently being delivered.
  """
  def mark_delivering(id) do
    NotificationQueueItem
    |> Repo.get!(id)
    |> NotificationQueueItem.changeset(%{status: "delivering"})
    |> Repo.update()
  end

  @doc """
  Mark a notification as successfully delivered with current timestamp.
  """
  def mark_delivered(id) do
    NotificationQueueItem
    |> Repo.get!(id)
    |> NotificationQueueItem.changeset(%{
      status: "delivered",
      delivered_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Mark a notification as permanently failed.
  """
  def mark_failed(id, error) do
    NotificationQueueItem
    |> Repo.get!(id)
    |> NotificationQueueItem.changeset(%{
      status: "failed",
      last_error: to_string(error)
    })
    |> Repo.update()
  end

  @doc """
  Increment retry count and schedule a retry with exponential backoff.

  Delays follow the sequence: 10s, 30s, 90s, 270s, max 810s.
  The notification is reset to "pending" so the next poll picks it up.
  """
  def increment_retry(id, error) do
    item = Repo.get!(NotificationQueueItem, id)
    new_retry_count = item.retry_count + 1

    # Exponential backoff: 10 * 3^(n-1) capped at 810s
    delay = min(round(:math.pow(3, new_retry_count - 1)) * 10, 810)
    scheduled_at = DateTime.add(DateTime.utc_now(), delay, :second)

    item
    |> NotificationQueueItem.changeset(%{
      retry_count: new_retry_count,
      last_error: to_string(error),
      scheduled_at: scheduled_at,
      status: "pending"
    })
    |> Repo.update()
  end

  @doc """
  Count the number of notifications currently in "pending" status.
  """
  def count_pending do
    NotificationQueueItem
    |> where([n], n.status == "pending")
    |> Repo.aggregate(:count, :id)
  end
end
