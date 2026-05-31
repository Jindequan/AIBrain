defmodule AIBrain.Plugin.Registry do
  @moduledoc """
  ETS-backed registry for installed plugins.

  Manages plugin lifecycle:
    * Install — download manifest, store metadata
    * Enable — register tools with Tool.Registry
    * Disable — unregister tools from Tool.Registry
    * Uninstall — remove plugin data and disable

  Each plugin is stored as an `%AIBrain.Plugin.PluginSpec{}` struct.
  """

  use GenServer
  require Logger

  alias AIBrain.Tool.Registry, as: ToolRegistry

  defstruct [
    :name,
    :version,
    :description,
    :author,
    :repository,
    :tools,
    :status,
    :path,
    :installed_at
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          description: String.t(),
          author: String.t() | nil,
          repository: String.t() | nil,
          tools: [atom()],
          status: :installed | :enabled | :disabled,
          path: String.t(),
          installed_at: integer()
        }

  # ── Client API ──

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "List all plugins."
  def list(server \\ __MODULE__), do: GenServer.call(server, :list)

  @doc "Get a single plugin by name."
  def get(server \\ __MODULE__, name), do: GenServer.call(server, {:get, name})

  @doc "Install a plugin from a manifest path."
  def install(server \\ __MODULE__, manifest_path) do
    GenServer.call(server, {:install, manifest_path})
  end

  @doc "Enable a plugin (register its tools)."
  def enable(server \\ __MODULE__, name), do: GenServer.call(server, {:enable, name})

  @doc "Disable a plugin (unregister its tools)."
  def disable(server \\ __MODULE__, name), do: GenServer.call(server, {:disable, name})

  @doc "Uninstall a plugin permanently."
  def uninstall(server \\ __MODULE__, name), do: GenServer.call(server, {:uninstall, name})

  @doc "Rescan the plugins directory for changes."
  def rescan(server \\ __MODULE__), do: GenServer.call(server, :rescan)

  # ── Server callbacks ──

  @impl true
  def init(opts) do
    base_path = Keyword.get(opts, :base_path) || default_base_path()
    File.mkdir_p!(base_path)

    table = :ets.new(:plugin_registry, [:set, :public, read_concurrency: true])
    {:ok, %{base_path: base_path, table: table}, {:continue, :scan}}
  end

  @impl true
  def handle_continue(:scan, state) do
    scan_directory(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    plugins = :ets.tab2list(state.table) |> Enum.map(fn {_name, spec} -> spec end)
    {:reply, plugins, state}
  end

  def handle_call({:get, name}, _from, state) do
    reply =
      case :ets.lookup(state.table, name) do
        [{^name, spec}] -> {:ok, spec}
        [] -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:install, manifest_path}, _from, state) do
    result = do_install(state, manifest_path)
    {:reply, result, state}
  end

  def handle_call({:enable, name}, _from, state) do
    result = do_enable(state, name)
    {:reply, result, state}
  end

  def handle_call({:disable, name}, _from, state) do
    result = do_disable(state, name)
    {:reply, result, state}
  end

  def handle_call({:uninstall, name}, _from, state) do
    result = do_uninstall(state, name)
    {:reply, result, state}
  end

  def handle_call(:rescan, _from, state) do
    :ets.delete_all_objects(state.table)
    scan_directory(state)

    plugins = :ets.tab2list(state.table) |> Enum.map(fn {_name, spec} -> spec end)
    {:reply, plugins, state}
  end

  # ── Private ──

  defp scan_directory(state) do
    if File.dir?(state.base_path) do
      state.base_path
      |> File.ls!()
      |> Enum.each(fn dir_name ->
        plugin_path = Path.join(state.base_path, dir_name)
        manifest_path = Path.join(plugin_path, "plugin.json")

        if File.dir?(plugin_path) and File.exists?(manifest_path) do
          case load_manifest(manifest_path) do
            {:ok, spec} ->
              :ets.insert(state.table, {spec.name, spec})

              # Register tools for enabled plugins
              if spec.status == :enabled do
                Enum.each(spec.tools, &register_tool/1)
              end

            {:error, reason} ->
              Logger.warning("Plugin.Registry: failed to load #{manifest_path}: #{reason}")
          end
        end
      end)
    end
  end

  defp load_manifest(path) do
    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json),
         {:ok, name} <- Map.fetch(data, "name"),
         version <- Map.get(data, "version", "0.1.0"),
         tools when is_list(tools) <- Map.get(data, "tools", []) do
      tool_modules =
        Enum.map(tools, fn tool_name ->
          try do
            mod = Module.concat([tool_name])
            Code.ensure_loaded(mod)
            mod
          rescue
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      spec = %__MODULE__{
        name: name,
        version: version,
        description: Map.get(data, "description", ""),
        author: Map.get(data, "author"),
        repository: Map.get(data, "repository"),
        tools: tool_modules,
        status: parse_status(Map.get(data, "status", "enabled")),
        path: Path.dirname(path),
        installed_at: Map.get(data, "installed_at", System.system_time(:second))
      }

      {:ok, spec}
    else
      {:error, reason} -> {:error, inspect(reason)}
      :error -> {:error, "missing required field: name"}
      false -> {:error, "tools must be a list"}
    end
  end

  defp do_install(state, manifest_path) do
    case load_manifest(manifest_path) do
      {:ok, spec} ->
        # Copy manifest and code to plugins directory
        dest = Path.join(state.base_path, spec.name)
        File.mkdir_p!(dest)

        # Copy plugin.json
        File.cp!(manifest_path, Path.join(dest, "plugin.json"))

        # Copy lib/ directory if it exists
        src_lib = Path.join(Path.dirname(manifest_path), "lib")

        if File.dir?(src_lib) do
          dest_lib = Path.join(dest, "lib")
          File.mkdir_p!(dest_lib)
          File.cp_r!(src_lib, dest_lib)
        end

        # Register in ETS
        installed_spec = %{
          spec
          | path: dest,
            status: :enabled,
            installed_at: System.system_time(:second)
        }

        :ets.insert(state.table, {spec.name, installed_spec})

        # Enable tools if status is enabled
        if installed_spec.status == :enabled do
          Enum.each(installed_spec.tools, &register_tool/1)
        end

        {:ok, installed_spec}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_enable(state, name) do
    case :ets.lookup(state.table, name) do
      [{^name, spec}] ->
        updated = %{spec | status: :enabled}
        :ets.insert(state.table, {name, updated})
        Enum.each(spec.tools, &register_tool/1)

        # Update manifest
        update_manifest_status(spec.path, "enabled")
        {:ok, updated}

      [] ->
        {:error, :not_found}
    end
  end

  defp do_disable(state, name) do
    case :ets.lookup(state.table, name) do
      [{^name, spec}] ->
        updated = %{spec | status: :disabled}
        :ets.insert(state.table, {name, updated})
        Enum.each(spec.tools, &unregister_tool/1)

        # Update manifest
        update_manifest_status(spec.path, "disabled")
        {:ok, updated}

      [] ->
        {:error, :not_found}
    end
  end

  defp do_uninstall(state, name) do
    case :ets.lookup(state.table, name) do
      [{^name, spec}] ->
        # Disable tools first
        Enum.each(spec.tools, &unregister_tool/1)

        # Remove from ETS
        :ets.delete(state.table, name)

        # Remove from filesystem
        if File.dir?(spec.path) do
          File.rm_rf!(spec.path)
        end

        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp register_tool(module) do
    if function_exported?(module, :name, 0) do
      ToolRegistry.register(ToolRegistry, module)
      Logger.debug("Plugin: registered tool #{module.name()}")
    end
  rescue
    e -> Logger.warning("Plugin: failed to register tool #{inspect(module)}: #{inspect(e)}")
  end

  defp unregister_tool(module) do
    if function_exported?(module, :name, 0) do
      ToolRegistry.unregister(ToolRegistry, module.name())
      Logger.debug("Plugin: unregistered tool #{module.name()}")
    end
  rescue
    e -> Logger.warning("Plugin: failed to unregister tool #{inspect(module)}: #{inspect(e)}")
  end

  defp update_manifest_status(plugin_path, status) do
    manifest_path = Path.join(plugin_path, "plugin.json")

    with {:ok, json} <- File.read(manifest_path),
         {:ok, data} <- Jason.decode(json) do
      updated = Map.put(data, "status", status)
      File.write!(manifest_path, Jason.encode!(updated, pretty: true))
    end
  rescue
    _ -> :ok
  end

  defp parse_status("enabled"), do: :enabled
  defp parse_status("disabled"), do: :disabled
  defp parse_status("installed"), do: :installed
  defp parse_status(_), do: :enabled

  defp default_base_path do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join(data_dir, "plugins")
  end
end
