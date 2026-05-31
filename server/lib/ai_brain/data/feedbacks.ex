defmodule AIBrain.Data.Feedbacks do
  @moduledoc """
  CRUD for feedback entries — user corrections on any system decision.
  """

  import Ecto.Query

  alias AIBrain.Repo
  alias AIBrain.Data.Feedback

  @doc "Create a feedback entry."
  def create(attrs) when is_map(attrs) do
    %Feedback{}
    |> Feedback.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List feedback entries, optionally filtered."
  def list(opts \\ []) do
    query = from(f in Feedback, order_by: [desc: f.inserted_at])

    query =
      case Keyword.get(opts, :target_type) do
        nil -> query
        t -> from(f in query, where: f.target_type == ^t)
      end

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        s -> from(f in query, where: f.status == ^s)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        n -> from(f in query, limit: ^n)
      end

    Repo.all(query)
  end

  @doc "Get a feedback entry by ID."
  def get(id) do
    Repo.get(Feedback, id)
  end

  @doc "Update feedback entry status."
  def update_status(id, status) do
    Repo.get(Feedback, id)
    |> case do
      nil -> {:error, :not_found}
      feedback -> Repo.update(Ecto.Changeset.change(feedback, status: status))
    end
  end

  @doc "Get unprocessed feedback for a target type."
  def pending_for(target_type) do
    Repo.all(
      from(f in Feedback,
        where: f.target_type == ^target_type and f.status == "pending",
        order_by: [asc: f.inserted_at]
      )
    )
  end

  @doc "Count feedback entries per target type."
  def counts do
    Repo.all(
      from(f in Feedback,
        group_by: f.target_type,
        select: %{target_type: f.target_type, count: count(f.id)}
      )
    )
  end
end
