defmodule AIBrain.Tool.Registry do
  use GenServer

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, %{})
      name -> GenServer.start_link(__MODULE__, %{}, name: name)
    end
  end

  def register(server \\ __MODULE__, module) do
    GenServer.call(server, {:register, module})
  end

  def lookup(server \\ __MODULE__, name) do
    GenServer.call(server, {:lookup, name})
  end

  def unregister(server \\ __MODULE__, name) do
    GenServer.call(server, {:unregister, name})
  end

  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  end

  @doc """
  Check if a tool is available on the current system.
  Tools that don't implement `available?/0` default to true.
  """
  def available?(server \\ __MODULE__, tool_name) do
    case lookup(server, tool_name) do
      {:ok, mod} ->
        if function_exported?(mod, :available?, 0),
          do: mod.available?(),
          else: true

      _ ->
        false
    end
  end

  @doc """
  Format all registered tools for API consumption.
  Excludes tools whose `available?/0` returns false and
  tools whose `skill_owner` is not in the active skills list.
  """
  def to_api_format(server \\ __MODULE__, opts \\ []) do
    active_skills = Keyword.get(opts, :active_skills, :all)

    server
    |> all()
    |> Enum.filter(fn mod ->
      available?(server, mod.name()) and skill_filter(mod, active_skills)
    end)
    |> Enum.map(fn mod ->
      %{
        "name" => mod.name(),
        "description" => mod.description(),
        "input_schema" => atomize_keys_to_strings(mod.input_schema())
      }
    end)
  end

  defp skill_filter(_mod, :all), do: true

  defp skill_filter(mod, skills) when is_list(skills) do
    owner = if function_exported?(mod, :skill_owner, 0), do: mod.skill_owner(), else: nil
    is_nil(owner) or owner in skills
  end

  defp atomize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), atomize_keys_to_strings(v)}
      {k, v} -> {k, atomize_keys_to_strings(v)}
    end)
  end

  defp atomize_keys_to_strings(list) when is_list(list) do
    Enum.map(list, &atomize_keys_to_strings/1)
  end

  defp atomize_keys_to_strings(value), do: value

  def read_only?(server \\ __MODULE__, tool_name) do
    case lookup(server, tool_name) do
      {:ok, mod} -> mod.read_only?()
      _ -> false
    end
  end

  def risk_category(server \\ __MODULE__, tool_name) do
    case lookup(server, tool_name) do
      {:ok, mod} ->
        cond do
          function_exported?(mod, :risk_category, 0) -> mod.risk_category()
          mod.read_only?() -> :read_only
          tool_name == "bash" -> :shell_exec
          tool_name in ["file_write", "file_edit"] -> :workspace_write
          true -> :unknown
        end

      _ ->
        :unknown
    end
  end

  def init(state), do: {:ok, state}

  def handle_call({:lookup, name}, _from, state) do
    case Map.get(state, name) do
      nil -> {:reply, {:error, :not_found}, state}
      mod -> {:reply, {:ok, mod}, state}
    end
  end

  def handle_call(:all, _from, state) do
    {:reply, Map.values(state), state}
  end

  def handle_call({:register, mod}, _from, state) do
    {:reply, :ok, Map.put(state, mod.name(), mod)}
  end

  def handle_call({:unregister, name}, _from, state) do
    if Map.has_key?(state, name) do
      {:reply, :ok, Map.delete(state, name)}
    else
      {:reply, {:error, :not_found}, state}
    end
  end
end
