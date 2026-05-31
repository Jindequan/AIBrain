defmodule AIBrain.Permissions.AutonomyTest do
  use ExUnit.Case, async: true

  alias AIBrain.Permissions.Autonomy
  alias AIBrain.Tool.Registry

  setup do
    {:ok, registry} = Registry.start_link(name: nil)
    :ok = Registry.register(registry, AIBrain.Tool.Builtin.FileRead)
    :ok = Registry.register(registry, AIBrain.Tool.Builtin.FileWrite)
    :ok = Registry.register(registry, AIBrain.Tool.Builtin.Bash)
    %{registry: registry}
  end

  test "level 0 never auto-allows", %{registry: registry} do
    refute Autonomy.auto_allowed?(0, "file_read", registry)
    refute Autonomy.auto_allowed?(0, "bash", registry)
  end

  test "level 1 allows read-only tools only", %{registry: registry} do
    assert Autonomy.auto_allowed?(1, "file_read", registry)
    refute Autonomy.auto_allowed?(1, "bash", registry)
  end

  test "level 2 allows workspace and network but not shell", %{registry: registry} do
    assert Autonomy.auto_allowed?(2, "file_read", registry)
    assert Autonomy.auto_allowed?(2, "file_write", registry)
    refute Autonomy.auto_allowed?(2, "bash", registry)
  end
end
