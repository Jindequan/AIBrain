defmodule AIBrain.Web.Handlers.UserPromptsHandler do
  @moduledoc """
  REST API for user-level prompt management.

  These are user-defined prompts for business/custom use cases,
  separate from system prompts that power core AIBrain functionality.
  """

  import Plug.Conn
  alias AIBrain.Data.UserPrompts
  alias AIBrain.Data.UserPrompt

  @doc """
  GET /api/user-prompts

  Lists all your active prompts.
  """
  def handle_list(conn) do
    prompts = UserPrompts.list()

    json_response(conn, 200, %{
      prompts: Enum.map(prompts, &format_prompt/1)
    })
  end

  @doc """
  GET /api/user-prompts/:id

  Gets a specific prompt.
  """
  def handle_get(conn, id) do
    case UserPrompts.get(id) do
      nil ->
        json_response(conn, 404, %{error: "Prompt not found"})

      prompt ->
        json_response(conn, 200, %{prompt: format_prompt(prompt)})
    end
  end

  @doc """
  POST /api/user-prompts

  Creates a new user prompt.
  """
  def handle_create(conn) do
    params = conn.body_params

    attrs = %{
      name: Map.get(params, "name"),
      category: Map.get(params, "category"),
      template: Map.get(params, "template"),
      variables: encode_variables(Map.get(params, "variables", [])),
      description: Map.get(params, "description")
    }

    case UserPrompts.create(attrs) do
      {:ok, prompt} ->
        json_response(conn, 201, %{prompt: format_prompt(prompt)})

      {:error, changeset} ->
        errors = format_errors(changeset)
        json_response(conn, 400, %{error: "Validation failed", errors: errors})
    end
  end

  @doc """
  PUT /api/user-prompts/:id

  Updates an existing prompt.
  """
  def handle_update(conn, id) do
    params = conn.body_params

    attrs = %{
      name: Map.get(params, "name"),
      category: Map.get(params, "category"),
      template: Map.get(params, "template"),
      variables: encode_variables(Map.get(params, "variables", [])),
      description: Map.get(params, "description"),
      is_active: Map.get(params, "is_active", true)
    }

    case UserPrompts.update(id, attrs) do
      {:ok, prompt} ->
        json_response(conn, 200, %{prompt: format_prompt(prompt)})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Prompt not found"})

      {:error, changeset} ->
        errors = format_errors(changeset)
        json_response(conn, 400, %{error: "Validation failed", errors: errors})
    end
  end

  @doc """
  DELETE /api/user-prompts/:id

  Soft deletes a prompt (sets is_active = false).
  """
  def handle_delete(conn, id) do
    case UserPrompts.delete(id) do
      {:ok, prompt} ->
        json_response(conn, 200, %{message: "Prompt deleted", prompt: format_prompt(prompt)})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Prompt not found"})
    end
  end

  @doc """
  POST /api/user-prompts/:id/render

  Renders a prompt template with provided variables.
  """
  def handle_render(conn, id) do
    variables = conn.body_params["variables"] || %{}

    case UserPrompts.render(id, variables) do
      {:ok, rendered} ->
        json_response(conn, 200, %{rendered: rendered})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Prompt not found"})
    end
  end

  # Private functions

  defp format_prompt(%UserPrompt{} = prompt) do
    variables =
      if prompt.variables do
        case Jason.decode(prompt.variables) do
          {:ok, vars} -> vars
          _ -> []
        end
      else
        []
      end

    %{
      id: prompt.id,
      name: prompt.name,
      category: prompt.category,
      template: prompt.template,
      variables: variables,
      description: prompt.description,
      is_active: prompt.is_active,
      created_at: prompt.inserted_at,
      updated_at: prompt.updated_at
    }
  end

  defp encode_variables(variables) when is_list(variables) do
    Jason.encode!(variables)
  end

  defp encode_variables(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {field, {msg, _opts}} ->
      "#{field}: #{msg}"
    end)
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
