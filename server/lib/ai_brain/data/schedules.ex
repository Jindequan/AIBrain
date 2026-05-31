defmodule AIBrain.Data.Schedules do
  @moduledoc """
  CRUD operations for the unified `schedules` table.
  """

  require Logger

  alias AIBrain.Repo
  alias AIBrain.Data.Schedule

  @doc """
  List schedules with optional filters.

  Supported options:
    - `:status` — filter by status string
    - `:trigger_type` — filter by trigger type string
  """
  @spec list_schedules(keyword()) :: [Schedule.t()]
  def list_schedules(opts \\ []) do
    import Ecto.Query

    status = Keyword.get(opts, :status)
    trigger_type = Keyword.get(opts, :trigger_type)

    query = from(s in Schedule, order_by: [desc: s.inserted_at])
    query = maybe_filter_status(query, status)
    query = maybe_filter_trigger_type(query, trigger_type)

    Repo.all(query)
  end

  @doc "Get a single schedule by ID."
  @spec get_schedule(String.t()) :: {:ok, Schedule.t()} | {:error, :not_found}
  def get_schedule(id) do
    case Repo.get(Schedule, id) do
      nil -> {:error, :not_found}
      schedule -> {:ok, schedule}
    end
  end

  @doc "Create a new schedule."
  @spec create_schedule(map()) :: {:ok, Schedule.t()} | {:error, term()}
  def create_schedule(attrs) when is_map(attrs) do
    %Schedule{}
    |> Schedule.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schedule} ->
        Logger.info("Schedule created: #{schedule.name} (#{schedule.id})")
        {:ok, schedule}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc "Update an existing schedule."
  @spec update_schedule(String.t(), map()) :: {:ok, Schedule.t()} | {:error, term()}
  def update_schedule(id, attrs) when is_map(attrs) do
    case Repo.get(Schedule, id) do
      nil ->
        {:error, :not_found}

      schedule ->
        schedule
        |> Schedule.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, inspect(changeset.errors)}
        end
    end
  end

  @doc "Delete a schedule by ID."
  @spec delete_schedule(String.t()) :: :ok | {:error, term()}
  def delete_schedule(id) do
    case Repo.get(Schedule, id) do
      nil ->
        {:error, :not_found}

      schedule ->
        Repo.delete(schedule)
        :ok
    end
  end

  def diagnostics do
    schedules = list_schedules()

    counts =
      schedules
      |> Enum.frequencies_by(& &1.status)
      |> then(fn counts ->
        %{
          total: length(schedules),
          active: Map.get(counts, "active", 0),
          paused: Map.get(counts, "paused", 0),
          fired: Map.get(counts, "completed", 0),
          cancelled: Map.get(counts, "cancelled", 0)
        }
      end)

    upcoming =
      schedules
      |> Enum.filter(&(&1.status == "active" and not is_nil(&1.next_fire_at)))
      |> Enum.sort_by(& &1.next_fire_at, DateTime)
      |> Enum.take(10)
      |> Enum.map(fn schedule ->
        %{
          id: schedule.id,
          type: schedule.trigger_type,
          next_fire_at: schedule.next_fire_at,
          name: schedule.name
        }
      end)

    %{counts: counts, upcoming: upcoming}
  end

  @doc """
  Find all active schedules whose `next_fire_at` is in the past (or now).
  """
  @spec list_due_schedules :: [Schedule.t()]
  def list_due_schedules do
    import Ecto.Query

    now = DateTime.utc_now()

    query =
      from(s in Schedule,
        where: s.status == "active" and s.next_fire_at <= ^now,
        order_by: [asc: s.next_fire_at]
      )

    Repo.all(query)
  end

  # ── Private helpers ──

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_binary(status) do
    import Ecto.Query
    from(s in query, where: s.status == ^status)
  end

  defp maybe_filter_trigger_type(query, nil), do: query

  defp maybe_filter_trigger_type(query, trigger_type) when is_binary(trigger_type) do
    import Ecto.Query
    from(s in query, where: s.trigger_type == ^trigger_type)
  end
end
