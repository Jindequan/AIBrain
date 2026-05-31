defmodule AIBrain.Web.Handlers.AssistantsHandler do
  import Plug.Conn

  alias AIBrain.Skill.Manager
  alias AIBrain.Skill.Registry

  def handle_list_skills(conn) do
    skills = Enum.map(Manager.list(), &skill_summary/1)
    json(conn, 200, %{skills: skills})
  end

  def handle_get_skill(conn, name) do
    case Manager.get(name) do
      {:ok, spec} -> json(conn, 200, %{skill: skill_detail(spec)})
      {:error, :not_found} -> json(conn, 404, %{error: "Skill not found: #{name}"})
    end
  end

  def handle_create_skill(conn, params) do
    case Manager.create(params) do
      {:ok, spec} -> json(conn, 201, %{skill: skill_detail(spec)})
      {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
    end
  end

  def handle_update_skill(conn, name, params) do
    case Manager.update(name, params) do
      {:ok, spec} -> json(conn, 200, %{skill: skill_detail(spec)})
      {:error, :not_found} -> json(conn, 404, %{error: "Skill not found: #{name}"})
      {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
    end
  end

  def handle_delete_skill(conn, name) do
    case Manager.delete(name) do
      :ok -> json(conn, 200, %{status: "deleted"})
      {:error, :not_found} -> json(conn, 404, %{error: "Skill not found: #{name}"})
      {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
    end
  end

  def handle_toggle_skill(conn, name) do
    with {:ok, spec} <- Manager.get(name),
         next <- if(spec.status == :active, do: :paused, else: :active),
         {:ok, updated} <- Manager.set_status(name, next) do
      json(conn, 200, %{skill: skill_detail(updated)})
    else
      {:error, :not_found} -> json(conn, 404, %{error: "Skill not found"})
      {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
    end
  end

  def handle_install_skill(conn, params) do
    cond do
      is_binary(params["url"]) and params["url"] != "" ->
        case Manager.install_url(params["url"]) do
          {:ok, spec} -> json(conn, 201, %{skill: skill_detail(spec)})
          {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
        end

      is_binary(params["path"]) and params["path"] != "" ->
        case Manager.import_path(params["path"]) do
          {:ok, spec} -> json(conn, 201, %{skill: skill_detail(spec)})
          {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
        end

      true ->
        json(conn, 400, %{error: "Missing required field: url or path"})
    end
  end

  def handle_update_from_source(conn, name) do
    case Manager.update_from_source(name) do
      {:ok, spec} -> json(conn, 200, %{skill: skill_detail(spec)})
      {:error, :not_found} -> json(conn, 404, %{error: "Skill not found: #{name}"})
      {:error, reason} -> json(conn, 400, %{error: format_error(reason)})
    end
  end

  defp skill_summary(spec) do
    %{
      name: spec.name,
      description: spec.description,
      status: spec.status,
      origin: spec.origin,
      metadata: spec.metadata
    }
  end

  defp skill_detail(spec) do
    spec
    |> skill_summary()
    |> Map.merge(%{
      body: spec.body,
      source_uri: spec.source_uri,
      path: spec.path,
      root_path: spec.root_path,
      resources: spec.resources,
      builtin_path: Registry.builtin_path(),
      user_path: Registry.user_path()
    })
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
