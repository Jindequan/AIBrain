defmodule AIBrain.Data.EvidenceItems do
  @moduledoc """
  Context for evidence_items table — evidence ledger for agent runs.
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.EvidenceItem

  def create(attrs) when is_map(attrs) do
    %EvidenceItem{}
    |> EvidenceItem.changeset(attrs)
    |> Repo.insert()
  end

  def get(id) when is_binary(id) do
    case Repo.get(EvidenceItem, id) do
      nil -> {:error, :not_found}
      evidence -> {:ok, evidence}
    end
  end

  def list_for_run(run_id) do
    Repo.all(
      from(e in EvidenceItem,
        where: e.run_id == ^run_id,
        order_by: [asc: e.inserted_at]
      )
    )
  end

  def count_for_run(run_id) do
    Repo.aggregate(from(e in EvidenceItem, where: e.run_id == ^run_id), :count, :id)
  end

  def update_status(id, status) when is_binary(id) and is_binary(status) do
    case Repo.get(EvidenceItem, id) do
      nil ->
        {:error, :not_found}

      evidence ->
        evidence
        |> EvidenceItem.changeset(%{status: status})
        |> Repo.update()
    end
  end

  def list_active_for_run(run_id) do
    Repo.all(
      from(e in EvidenceItem,
        where: e.run_id == ^run_id,
        where: e.status == "active",
        order_by: [asc: e.inserted_at]
      )
    )
  end
end
