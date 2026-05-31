defmodule AIBrain.Permissions.PolicyTest do
  use ExUnit.Case, async: true

  alias AIBrain.Permissions.Policy
  alias AIBrain.Tool.Registry

  defmodule ReadTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "read_tool"
    def description, do: "read"
    def input_schema, do: %{}
    def read_only?, do: true
    def execute(_, _), do: {:ok, "read"}
  end

  defmodule WriteTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "write_tool"
    def description, do: "write"
    def input_schema, do: %{}
    def read_only?, do: false
    def risk_category, do: :workspace_write
    def execute(_, _), do: {:ok, "write"}
  end

  setup do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, ReadTool)
    Registry.register(reg, WriteTool)
    assert {:ok, ReadTool} = Registry.lookup(reg, "read_tool")
    assert {:ok, WriteTool} = Registry.lookup(reg, "write_tool")
    %{registry: reg}
  end

  test "plan mode blocks mutating tools but allows read-only tools", %{registry: reg} do
    assert {:allow, %{name: "read_tool"},
            %{decision: :allowed, reason: :plan_mode_read_only, risk: :read_only}} =
             Policy.authorize(%{id: "r1", name: "read_tool", input: %{}}, reg, mode: :plan)

    assert {:deny, "Tool write_tool blocked: plan_mode",
            %{decision: :denied, reason: :plan_mode, risk: :workspace_write}} =
             Policy.authorize(%{id: "w1", name: "write_tool", input: %{}}, reg, mode: :plan)
  end

  test "approval_required mode waits for resolver on mutating tools", %{registry: reg} do
    resolver = fn _tool_use -> :approve end

    assert {:allow, %{name: "write_tool"},
            %{decision: :approved, reason: :approval_granted, risk: :workspace_write}} =
             Policy.authorize(%{id: "w1", name: "write_tool", input: %{}}, reg,
               mode: :approval_required,
               approval_resolver: resolver
             )
  end
end
