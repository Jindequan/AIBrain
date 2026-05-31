defmodule AIBrain.Tool.RegistryUnregisterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Registry

  defmodule FakeTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "fake_tool_unregister_test"
    def description, do: "fake"
    def input_schema, do: %{}
    def execute(_args, _ctx), do: {:ok, "done"}
    def read_only?, do: true
    def risk_category, do: :read_only
  end

  setup do
    {:ok, pid} = Registry.start_link(name: nil)
    %{registry: pid}
  end

  test "unregister/2 removes a registered tool", %{registry: reg} do
    :ok = Registry.register(reg, FakeTool)
    assert {:ok, FakeTool} = Registry.lookup(reg, "fake_tool_unregister_test")
    assert :ok = Registry.unregister(reg, "fake_tool_unregister_test")
    assert {:error, :not_found} = Registry.lookup(reg, "fake_tool_unregister_test")
  end

  test "unregister/2 returns error for unknown tool", %{registry: reg} do
    assert {:error, :not_found} = Registry.unregister(reg, "no_such_tool")
  end
end
