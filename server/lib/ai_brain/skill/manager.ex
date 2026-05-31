defmodule AIBrain.Skill.Manager do
  @moduledoc """
  Skill lifecycle manager.

  Owns creation, update, deletion, local import, and URL installation for the
  single supported skill format: a directory containing `SKILL.md` plus optional
  `scripts/`, `references/`, `assets/`, and `agents/`.
  """

  alias AIBrain.Skill.{Registry, Spec}

  @resource_dirs ~w(scripts references assets agents)

  def list, do: Registry.list(registry())
  def get(name), do: Registry.get(registry(), name)

  def create(attrs) when is_map(attrs) do
    with {:ok, spec} <- build_spec(attrs),
         :ok <- ensure_user_skill_available(spec.name),
         :ok <- write_skill_dir(spec, user_skill_dir(spec.name), attrs),
         :ok <- Registry.rescan(registry()) do
      Registry.get(registry(), spec.name)
    end
  end

  def update(name, attrs) when is_binary(name) and is_map(attrs) do
    with {:ok, existing} <- Registry.get(registry(), name),
         :ok <- ensure_mutable(existing),
         {:ok, spec} <- merge_spec(existing, attrs),
         :ok <- write_skill_dir(spec, existing.root_path, attrs),
         :ok <- Registry.rescan(registry()) do
      Registry.get(registry(), spec.name)
    end
  end

  def delete(name) when is_binary(name) do
    with {:ok, spec} <- Registry.get(registry(), name),
         :ok <- ensure_mutable(spec),
         :ok <- remove_skill_dir(spec.root_path),
         :ok <- Registry.rescan(registry()) do
      :ok
    end
  end

  def set_status(name, status) when status in [:active, :paused, "active", "paused"] do
    normalized = parse_status(status)

    case Registry.get(registry(), name) do
      {:ok, %{origin: :builtin} = spec} ->
        shadow_dir = Path.join(Registry.user_path(), name)

        if normalized == :active do
          # Toggling back to active — remove the shadow so the builtin is used directly
          File.rm_rf(shadow_dir)
        else
          # Write a shadow SKILL.md in the user skill directory.
          # Registry scans user dir after builtin dir, so the shadow overrides.
          updated = %{spec | status: normalized}
          File.mkdir_p!(shadow_dir)
          File.write!(Path.join(shadow_dir, "SKILL.md"), Spec.render(updated))
        end

        Registry.rescan(registry())
        Registry.get(registry(), name)

      {:ok, _spec} ->
        update(name, %{"status" => to_string(normalized)})

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def import_path(path) when is_binary(path) do
    source_path =
      cond do
        File.regular?(path) and Path.basename(path) == "SKILL.md" -> Path.dirname(path)
        File.dir?(path) -> path
        true -> nil
      end

    with false <- is_nil(source_path),
         {:ok, spec} <- Spec.parse(Path.join(source_path, "SKILL.md"), origin: :external),
         :ok <- ensure_user_skill_available(spec.name),
         :ok <- copy_skill_dir(source_path, user_skill_dir(spec.name)),
         :ok <- Registry.rescan(registry()) do
      Registry.get(registry(), spec.name)
    else
      true -> {:error, :invalid_skill_path}
      other -> other
    end
  end

  def install_url(url) when is_binary(url) do
    with {:ok, content} <- fetch_content(url),
         {:ok, spec} <- Spec.parse_content(content, origin: :external, source_uri: url),
         :ok <- ensure_user_skill_available(spec.name),
         :ok <- write_skill_dir(spec, user_skill_dir(spec.name), %{}),
         :ok <- Registry.rescan(registry()) do
      Registry.get(registry(), spec.name)
    end
  end

  def update_from_source(name) when is_binary(name) do
    with {:ok, existing} <- Registry.get(registry(), name),
         :ok <- ensure_mutable(existing),
         source when is_binary(source) and source != "" <- existing.source_uri,
         {:ok, content} <- fetch_content(source),
         {:ok, spec} <- Spec.parse_content(content, origin: :external, source_uri: source),
         :ok <- write_skill_dir(spec, existing.root_path, %{}),
         :ok <- Registry.rescan(registry()) do
      Registry.get(registry(), spec.name)
    else
      nil -> {:error, :no_source_uri}
      "" -> {:error, :no_source_uri}
      other -> other
    end
  end

  defp build_spec(attrs) do
    body = string_value(attrs, "body") || string_value(attrs, :body) || ""

    spec = %Spec{
      name: string_value(attrs, "name") || string_value(attrs, :name),
      description: string_value(attrs, "description") || string_value(attrs, :description),
      body: body,
      path: "",
      root_path: "",
      origin: :user,
      source_uri: string_value(attrs, "source_uri") || string_value(attrs, :source_uri),
      metadata: metadata_value(attrs),
      status: parse_status(Map.get(attrs, "status") || Map.get(attrs, :status))
    }

    with :ok <- Spec.validate_name(spec.name),
         true <- is_binary(spec.description) and spec.description != "" do
      {:ok, spec}
    else
      false -> {:error, "missing required field: description"}
      other -> other
    end
  end

  defp merge_spec(%Spec{} = existing, attrs) do
    renamed = string_value(attrs, "name") || string_value(attrs, :name) || existing.name

    spec = %{
      existing
      | name: renamed,
        description:
          string_value(attrs, "description") || string_value(attrs, :description) ||
            existing.description,
        body: string_value(attrs, "body") || string_value(attrs, :body) || existing.body,
        source_uri:
          string_value(attrs, "source_uri") || string_value(attrs, :source_uri) ||
            existing.source_uri,
        metadata: metadata_value(attrs, existing.metadata),
        status: parse_status(Map.get(attrs, "status") || Map.get(attrs, :status) || existing.status)
    }

    with :ok <- Spec.validate_name(spec.name),
         :ok <- ensure_rename_available(existing.name, spec.name) do
      {:ok, spec}
    end
  end

  defp write_skill_dir(%Spec{} = spec, dir, attrs) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "SKILL.md"), Spec.render(spec))
    write_resources(dir, attrs)
    :ok
  rescue
    _ -> {:error, :write_failed}
  end

  defp write_resources(dir, attrs) do
    resources = Map.get(attrs, "resources") || Map.get(attrs, :resources) || %{}

    Enum.each(@resource_dirs, fn resource_dir ->
      case Map.get(resources, resource_dir) || Map.get(resources, String.to_atom(resource_dir)) do
        files when is_map(files) ->
          target_dir = Path.join(dir, resource_dir)
          File.mkdir_p!(target_dir)

          Enum.each(files, fn {relative, content} ->
            safe_relative = safe_relative_path!(to_string(relative))
            target = Path.join(target_dir, safe_relative)
            File.mkdir_p!(Path.dirname(target))
            File.write!(target, to_string(content))
          end)

        _ ->
          :ok
      end
    end)
  end

  defp copy_skill_dir(source, target) do
    File.rm_rf!(target)
    File.mkdir_p!(Path.dirname(target))

    case File.cp_r(source, target) do
      {:ok, _} -> :ok
      {:error, _file, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :copy_failed}
  end

  defp remove_skill_dir(path) do
    if is_binary(path) and path != "" do
      File.rm_rf!(path)
      :ok
    else
      {:error, :invalid_skill_path}
    end
  rescue
    _ -> {:error, :delete_failed}
  end

  defp ensure_user_skill_available(name) do
    case Registry.get(registry(), name) do
      {:error, :not_found} -> :ok
      {:ok, _} -> {:error, :already_exists}
    end
  end

  defp ensure_rename_available(current_name, current_name), do: :ok

  defp ensure_rename_available(_current_name, new_name) do
    ensure_user_skill_available(new_name)
  end

  defp ensure_mutable(%Spec{origin: :builtin}), do: {:error, :builtin_skill_immutable}
  defp ensure_mutable(%Spec{}), do: :ok

  defp user_skill_dir(name), do: Path.join(Registry.user_path(), name)

  defp registry, do: Process.get(:skill_registry, Registry)

  defp fetch_content(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, to_string(body)}
      {:ok, %{status: _}} -> {:error, :fetch_failed}
      {:error, _} -> {:error, :fetch_failed}
    end
  rescue
    _ -> {:error, :fetch_failed}
  end

  defp string_value(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp metadata_value(attrs, default \\ %{}) do
    case Map.get(attrs, "metadata") || Map.get(attrs, :metadata) do
      metadata when is_map(metadata) -> Map.new(metadata, fn {k, v} -> {to_string(k), v} end)
      _ -> default || %{}
    end
  end

  defp parse_status("paused"), do: :paused
  defp parse_status(:paused), do: :paused
  defp parse_status(_), do: :active

  defp safe_relative_path!(path) do
    if Path.type(path) == :absolute or ".." in Path.split(path) do
      raise ArgumentError, "path traversal is not allowed"
    end

    path
  end
end
