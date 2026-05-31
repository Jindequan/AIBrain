defmodule AIBrain.Data.UserPrompts do
  @moduledoc """
  CRUD operations for User Prompts.
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.UserPrompt

  @doc "List all active prompts"
  def list do
    Repo.all(
      from(p in UserPrompt,
        where: p.is_active == true,
        order_by: [desc: p.updated_at]
      )
    )
  end

  @doc "Get a prompt by ID"
  def get(id) do
    Repo.get(UserPrompt, id)
  end

  @doc "Create a new prompt"
  def create(attrs) do
    %UserPrompt{}
    |> UserPrompt.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a prompt"
  def update(id, attrs) do
    case get(id) do
      nil -> {:error, :not_found}
      prompt -> prompt |> UserPrompt.changeset(attrs) |> Repo.update()
    end
  end

  @doc "Delete a prompt (soft delete by setting is_active = false)"
  def delete(id) do
    case get(id) do
      nil -> {:error, :not_found}
      prompt -> prompt |> UserPrompt.changeset(%{is_active: false}) |> Repo.update()
    end
  end

  @doc "Render a prompt template by replacing variables"
  def render(id, variables) when is_map(variables) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %UserPrompt{template: template} ->
        rendered = replace_variables(template, variables)
        {:ok, rendered}
    end
  end

  defp replace_variables(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      placeholder = "{{#{key}}}"
      String.replace(acc, placeholder, to_string(value))
    end)
  end
end
