defmodule AIBrain.Task.RegistryWatcher do
  @moduledoc """
  Polls skills/ directory for file changes and triggers
  registry rescan when changes are detected.

  Enables hot-reload of skill definitions while the server runs.
  """

  use GenServer
  require Logger

  alias AIBrain.Skill.Registry, as: SkRegistry

  @poll_interval_ms 5_000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    state = %{known: %{}}

    state = %{state | known: scan_all()}
    schedule_tick()
    Logger.info("RegistryWatcher: watching skills dir every #{div(@poll_interval_ms, 1000)}s")
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    current = scan_all()

    if current != state.known do
      Logger.info("RegistryWatcher: skill files changed, rescaling")
      SkRegistry.rescan()

      schedule_tick()
      {:noreply, %{state | known: current}}
    else
      schedule_tick()
      {:noreply, state}
    end
  end

  defp scan_all do
    [SkRegistry.builtin_path(), SkRegistry.user_path()]
    |> Enum.flat_map(&SkRegistry.skill_entrypoints/1)
    |> Enum.reduce(%{}, fn path, acc ->
      case File.stat(path) do
        {:ok, stat} -> Map.put(acc, path, stat.mtime)
        _ -> acc
      end
    end)
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @poll_interval_ms)
end
