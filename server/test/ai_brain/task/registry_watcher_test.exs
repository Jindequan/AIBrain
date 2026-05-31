defmodule AIBrain.Task.RegistryWatcherTest do
  use ExUnit.Case, async: true

  alias AIBrain.Task.RegistryWatcher

  describe "file change detection" do
    test "registers watcher module" do
      assert is_list(RegistryWatcher.module_info(:exports))
    end

    test "start_link succeeds with custom name" do
      assert {:ok, pid} = start_supervised({RegistryWatcher, [name: :watcher_test]})
      assert is_pid(pid)
    end
  end
end
