defmodule AIBrain.Data.Events do
  @moduledoc """
  Context for events table — append-only event log (Event Store).
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.Event

  @doc "Create a new event record"
  def create(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List events for a goal, ordered by inserted_at"
  def list_by_goal(goal_id, opts \\ []) do
    query = from(e in Event, where: e.goal_id == ^goal_id, order_by: [asc: e.inserted_at])
    apply_opts(query, opts) |> Repo.all()
  end

  @doc "List events for a session, ordered by inserted_at"
  def list_by_session(session_id, opts \\ []) do
    query = from(e in Event, where: e.session_id == ^session_id, order_by: [asc: e.inserted_at])
    apply_opts(query, opts) |> Repo.all()
  end

  @doc "List all events in a correlation chain, ordered by inserted_at"
  def list_by_correlation(correlation_id) do
    Repo.all(
      from(e in Event, where: e.correlation_id == ^correlation_id, order_by: [asc: e.inserted_at])
    )
  end

  @doc "List events that haven't been snapshotted/distilled (no snapshot_id set)"
  def list_undistilled(limit \\ 100) do
    Repo.all(
      from(e in Event,
        where: is_nil(e.snapshot_id),
        limit: ^limit,
        order_by: [asc: e.inserted_at]
      )
    )
  end

  @doc "Mark a set of events as distilled by setting snapshot_id"
  def mark_distilled(event_ids) do
    Repo.update_all(
      from(e in Event, where: e.id in ^event_ids),
      set: [snapshot_id: "distilled"]
    )
  end

  @doc "List events for a task, ordered by inserted_at"
  def list_by_task(task_id, opts \\ []) do
    query = from(e in Event, where: e.task_id == ^task_id, order_by: [asc: e.inserted_at])
    apply_opts(query, opts) |> Repo.all()
  end

  @doc "Count events that haven't been distilled yet"
  def count_undistilled do
    Repo.aggregate(from(e in Event, where: is_nil(e.snapshot_id)), :count, :id)
  end

  defp apply_opts(query, opts) do
    query
    |> then(fn q ->
      if limit = Keyword.get(opts, :limit), do: from(e in q, limit: ^limit), else: q
    end)
    |> then(fn q ->
      if since = Keyword.get(opts, :since),
        do: from(e in q, where: e.inserted_at >= ^since),
        else: q
    end)
  end
end
