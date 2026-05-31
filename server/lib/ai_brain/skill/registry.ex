defmodule AIBrain.Skill.Registry do
  @moduledoc """
  Runtime registry for Codex-style skills.

  The registry scans two roots:

    * bundled built-ins under `priv/skills/.system`
    * user-installed skills under `$data_dir/skills`

  Every skill is a directory with one `SKILL.md`. User skills with the same
  name replace bundled skills in the registry.
  """

  use GenServer
  require Logger

  alias AIBrain.Skill.Spec

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def list(server \\ __MODULE__), do: GenServer.call(server, :list)
  def list_active(server \\ __MODULE__), do: server |> list() |> Enum.filter(&(&1.status == :active))
  def get(server \\ __MODULE__, name), do: GenServer.call(server, {:get, name})
  def rescan(server \\ __MODULE__), do: GenServer.call(server, :rescan)

  @doc "Returns compact metadata that can stay in prompt context for routing."
  def catalog(server \\ __MODULE__) do
    server
    |> list_active()
    |> Enum.map(fn skill ->
      %{
        name: skill.name,
        description: skill.description,
        origin: skill.origin,
        metadata: skill.metadata
      }
    end)
  end

  @impl true
  def init(opts) do
    table = :ets.new(:skill_registry, [:set, :public])

    state = %{
      table: table,
      builtin_path: Keyword.get(opts, :builtin_path) || builtin_path(),
      user_path: Keyword.get(opts, :user_path) || user_path()
    }

    {:ok, state, {:continue, :scan}}
  end

  @impl true
  def handle_continue(:scan, state) do
    scan_all(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    specs =
      state.table
      |> :ets.tab2list()
      |> Enum.map(fn {_name, spec} -> spec end)
      |> Enum.sort_by(& &1.name)

    {:reply, specs, state}
  end

  def handle_call({:get, name}, _from, state) do
    reply =
      case :ets.lookup(state.table, name) do
        [{^name, spec}] -> {:ok, spec}
        [] -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call(:rescan, _from, state) do
    :ets.delete_all_objects(state.table)
    scan_all(state)
    {:reply, :ok, state}
  end

  defp scan_all(state) do
    scan_root(state.table, state.builtin_path, :builtin)
    scan_root(state.table, state.user_path, :user)
  end

  defp scan_root(table, root, origin) do
    root
    |> skill_entrypoints()
    |> Enum.each(fn path ->
      case Spec.parse(path, origin: origin) do
        {:ok, spec} ->
          :ets.insert(table, {spec.name, spec})

        {:error, reason} ->
          Logger.warning("Skill.Registry: failed to parse #{path}: #{inspect(reason)}")
      end
    end)
  end

  def skill_entrypoints(root) when is_binary(root) do
    if File.dir?(root) do
      root
      |> File.ls!()
      |> Enum.map(&Path.join([root, &1, "SKILL.md"]))
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
    else
      []
    end
  rescue
    _ -> []
  end

  def builtin_path do
    case :code.priv_dir(:ai_brain) do
      path when is_list(path) -> Path.join([List.to_string(path), "skills", ".system"])
      {:error, _} -> Path.expand("priv/skills/.system")
    end
  end

  def user_path do
    data_dir = Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))
    Path.join(data_dir, "skills")
  end
end
