defmodule AIBrain.Data.SystemLessons do
  @moduledoc """
  CRUD for system lessons — distilled rules from user feedback.
  """

  import Ecto.Query

  alias AIBrain.Repo
  alias AIBrain.Data.SystemLesson

  @doc "Create a lesson."
  def create(attrs) when is_map(attrs) do
    %SystemLesson{}
    |> SystemLesson.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get active lessons for a target type."
  def active_for(target_type) do
    Repo.all(
      from(l in SystemLesson,
        where: l.target_type == ^target_type and l.active == true,
        order_by: [desc: l.version]
      )
    )
  end

  @doc "Get all lessons for a target type (including inactive)."
  def list(target_type) do
    Repo.all(
      from(l in SystemLesson,
        where: l.target_type == ^target_type,
        order_by: [desc: l.version]
      )
    )
  end

  @doc "Get a single lesson by ID."
  def get(id) do
    Repo.get(SystemLesson, id)
  end

  @doc "Activate a lesson (deactivates previous active version for same target)."
  def activate(id) do
    lesson = Repo.get(SystemLesson, id)

    case lesson do
      nil ->
        {:error, :not_found}

      %{target_type: target_type} ->
        # Deactivate all active lessons of same target
        Repo.update_all(
          from(l in SystemLesson, where: l.target_type == ^target_type and l.active == true),
          set: [active: false]
        )

        # Activate the chosen one
        Repo.update(Ecto.Changeset.change(lesson, active: true))
    end
  end

  @doc "Format lessons as text snippet for prompt injection."
  def format_for_prompt(target_type) do
    lessons = active_for(target_type)

    case lessons do
      [] ->
        ""

      list ->
        lines = Enum.map(list, fn l -> "- #{l.lesson}" end)

        (["\n## Historical Lessons", "The following corrections have been made in the past:", ""] ++
           lines)
        |> Enum.join("\n")
    end
  end
end
