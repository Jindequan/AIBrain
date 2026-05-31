defmodule AIBrain.Data.RunContextRefs do
  @moduledoc """
  CRUD helpers for normalized run context references.
  """

  import Ecto.Query

  alias AIBrain.Data.RunContextRef
  alias AIBrain.Repo

  def create(attrs) when is_map(attrs) do
    %RunContextRef{}
    |> RunContextRef.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:run_id, :ref_type, :ref_id, :role]
    )
  end

  def create_many(run_id, refs) when is_list(refs) do
    Enum.each(refs, fn ref ->
      ref
      |> Map.new()
      |> Map.put(:run_id, run_id)
      |> create()
    end)

    :ok
  end

  def list_for_run(run_id) do
    Repo.all(
      from(r in RunContextRef,
        where: r.run_id == ^run_id,
        order_by: [asc: r.role, asc: r.ref_type]
      )
    )
  end

  def list_for_ref(ref_type, ref_id) do
    Repo.all(
      from(r in RunContextRef,
        where: r.ref_type == ^ref_type and r.ref_id == ^ref_id,
        order_by: [desc: r.inserted_at]
      )
    )
  end
end
