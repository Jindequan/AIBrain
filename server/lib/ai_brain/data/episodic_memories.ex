defmodule AIBrain.Data.EpisodicMemories do
  @moduledoc """
  Context for episodic_memories table — goal-level task history.
  """
  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.EpisodicMemory

  @doc "Create a new episodic memory record"
  def create(attrs) do
    %EpisodicMemory{}
    |> EpisodicMemory.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get episodic memories for a goal, ordered by inserted_at descending"
  def get_by_goal(goal_id, opts \\ []) do
    query =
      from(em in EpisodicMemory,
        where: em.goal_id == ^goal_id,
        order_by: [desc: em.inserted_at]
      )

    query =
      if limit = Keyword.get(opts, :limit), do: from(em in query, limit: ^limit), else: query

    Repo.all(query)
  end

  @doc "Get episodic memories for a task, ordered by inserted_at descending"
  def get_by_task(task_id) do
    Repo.all(
      from(em in EpisodicMemory,
        where: em.task_id == ^task_id,
        order_by: [desc: em.inserted_at]
      )
    )
  end

  @doc "List most recent episodic memories"
  def list_recent(limit \\ 10) do
    Repo.all(
      from(em in EpisodicMemory,
        order_by: [desc: em.inserted_at],
        limit: ^limit
      )
    )
  end

  @doc "Count episodic memories for a goal"
  def count_by_goal(goal_id) do
    Repo.aggregate(from(em in EpisodicMemory, where: em.goal_id == ^goal_id), :count, :id)
  end
end
