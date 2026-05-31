defmodule AIBrain.DevReloader do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    filesystem = Module.concat([FileSystem])

    unless Code.ensure_loaded?(filesystem) do
      Logger.warning("DevReloader disabled: file_system dependency is not available")
      {:ok, %{watcher: nil, timer: nil}}
    else
      start_watcher(filesystem)
    end
  end

  defp start_watcher(filesystem) do
    dirs = [Path.expand("lib")]
    {:ok, watcher} = apply(filesystem, :start_link, [[dirs: dirs]])
    apply(filesystem, :subscribe, [watcher])
    Logger.info("DevReloader watching lib/ for changes")
    {:ok, %{watcher: watcher, timer: nil}}
  end

  @impl true
  def handle_info({:file_event, _watcher, {path, _events}}, state) do
    if String.ends_with?(path, ".ex") and File.exists?(path) do
      # Debounce: cancel previous timer and recompile after 100ms
      if state.timer, do: Process.cancel_timer(state.timer)
      timer = Process.send_after(self(), :recompile, 100)
      {:noreply, %{state | timer: timer}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:recompile, state) do
    Logger.info("DevReloader: recompiling...")

    case Mix.Task.run("compile") do
      {:ok, _} -> Logger.info("DevReloader: recompilation ok")
      {:error, _} -> Logger.warning("DevReloader: recompilation had errors")
      other -> Logger.debug("DevReloader: compile result: #{inspect(other)}")
    end

    {:noreply, %{state | timer: nil}}
  end
end
