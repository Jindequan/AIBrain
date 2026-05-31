defmodule AIBrain.Web.Handlers.PluginsHandler do
  import Plug.Conn

  alias AIBrain.Plugin.Registry
  alias AIBrain.Plugin.Installer

  def handle_list(conn) do
    plugins = Registry.list()
    json(conn, 200, %{plugins: Enum.map(plugins, &format_plugin/1)})
  end

  def handle_get(conn, name) do
    case Registry.get(name) do
      {:ok, plugin} ->
        json(conn, 200, %{plugin: format_plugin(plugin)})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Plugin not found: #{name}"})
    end
  end

  def handle_install(conn, params) do
    url = Map.get(params, "url")

    cond do
      url && url != "" ->
        case Installer.install(url) do
          {:ok, spec} ->
            json(conn, 200, %{plugin: format_plugin(spec), message: "Plugin installed"})

          {:error, reason} ->
            json(conn, 400, %{error: "Installation failed: #{inspect(reason)}"})
        end

      path = Map.get(params, "path") ->
        case Installer.install_local(path) do
          {:ok, spec} ->
            json(conn, 200, %{plugin: format_plugin(spec), message: "Plugin installed"})

          {:error, reason} ->
            json(conn, 400, %{error: "Installation failed: #{inspect(reason)}"})
        end

      true ->
        json(conn, 400, %{error: "Either 'url' or 'path' parameter is required"})
    end
  end

  def handle_uninstall(conn, name) do
    case Installer.uninstall(name) do
      :ok ->
        json(conn, 200, %{message: "Plugin uninstalled: #{name}"})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Plugin not found: #{name}"})
    end
  end

  def handle_enable(conn, name) do
    case Registry.enable(name) do
      {:ok, spec} ->
        json(conn, 200, %{plugin: format_plugin(spec), message: "Plugin enabled"})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Plugin not found: #{name}"})
    end
  end

  def handle_disable(conn, name) do
    case Registry.disable(name) do
      {:ok, spec} ->
        json(conn, 200, %{plugin: format_plugin(spec), message: "Plugin disabled"})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Plugin not found: #{name}"})
    end
  end

  def handle_update(conn, name) do
    case Installer.update(name) do
      {:ok, spec} ->
        json(conn, 200, %{plugin: format_plugin(spec), message: "Plugin updated"})

      {:error, reason} ->
        json(conn, 400, %{error: "Update failed: #{inspect(reason)}"})
    end
  end

  defp format_plugin(plugin) do
    %{
      name: plugin.name,
      version: plugin.version,
      description: plugin.description,
      author: plugin.author,
      repository: plugin.repository,
      tools:
        Enum.map(plugin.tools, fn mod ->
          Code.ensure_loaded(mod)

          %{
            name: if(function_exported?(mod, :name, 0), do: mod.name(), else: inspect(mod)),
            description:
              if(function_exported?(mod, :description, 0), do: mod.description(), else: nil)
          }
        end),
      status: plugin.status,
      installed_at: plugin.installed_at
    }
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
