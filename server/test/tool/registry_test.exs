defmodule AIBrain.Tool.RegistryTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Registry

  defmodule FakeTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "fake"
    def description, do: "A fake tool"
    def input_schema, do: %{type: "object", properties: %{msg: %{type: "string"}}}
    def execute(%{"msg" => m}, _ctx), do: {:ok, "echo: #{m}"}
    def read_only?, do: true
  end

  test "register and lookup by name" do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, FakeTool)
    assert {:ok, FakeTool} = Registry.lookup(reg, "fake")
  end

  test "lookup returns error for unknown tool" do
    {:ok, reg} = Registry.start_link(name: nil)
    assert {:error, :not_found} = Registry.lookup(reg, "nonexistent")
  end

  test "to_api_format returns Anthropic tool definitions" do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, FakeTool)
    [tool_def] = Registry.to_api_format(reg)
    assert tool_def["name"] == "fake"
    assert tool_def["description"] == "A fake tool"
    assert tool_def["input_schema"]["type"] == "object"
  end

  test "read_only? returns true for read-only tool" do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, FakeTool)
    assert Registry.read_only?(reg, "fake")
  end

  test "risk_category defaults to read_only for read-only tools" do
    {:ok, reg} = Registry.start_link(name: nil)
    Registry.register(reg, FakeTool)
    assert Registry.risk_category(reg, "fake") == :read_only
  end
end

defmodule AIBrain.Tool.RegistryAvailTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Registry

  defmodule UnavailableTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "unavailable_tool"
    def description, do: "Never available"
    def input_schema, do: %{type: "object", properties: %{}}
    def execute(_args, _ctx), do: {:ok, "never runs"}
    def read_only?, do: true
    def available?, do: false
  end

  defmodule ConditionallyAvailableTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "cond_tool"
    def description, do: "Sometimes available"
    def input_schema, do: %{type: "object", properties: %{}}
    def execute(_args, _ctx), do: {:ok, "maybe"}
    def read_only?, do: true
    def available?, do: true
  end

  defmodule FakeAvailTool do
    @behaviour AIBrain.Tool.Behaviour
    def name, do: "fake_avail"
    def description, do: "A fake tool"
    def input_schema, do: %{type: "object", properties: %{}}
    def execute(%{"msg" => m}, _ctx), do: {:ok, "echo: #{m}"}
    def read_only?, do: true
  end

  describe "available?/2" do
    test "returns true for tools without available? callback" do
      {:ok, reg} = Registry.start_link(name: nil)
      Registry.register(reg, FakeAvailTool)
      assert Registry.available?(reg, "fake_avail") == true
    end

    test "returns false when tool implements available? as false" do
      {:ok, reg} = Registry.start_link(name: nil)
      Registry.register(reg, UnavailableTool)
      assert Registry.available?(reg, "unavailable_tool") == false
    end

    test "returns true when tool implements available? as true" do
      {:ok, reg} = Registry.start_link(name: nil)
      Registry.register(reg, ConditionallyAvailableTool)
      assert Registry.available?(reg, "cond_tool") == true
    end

    test "returns false for unknown tool" do
      {:ok, reg} = Registry.start_link(name: nil)
      assert Registry.available?(reg, "nonexistent") == false
    end
  end

  describe "to_api_format filters unavailable tools" do
    test "excludes tools where available? returns false" do
      {:ok, reg} = Registry.start_link(name: nil)
      Registry.register(reg, FakeAvailTool)
      Registry.register(reg, UnavailableTool)
      Registry.register(reg, ConditionallyAvailableTool)

      tools = Registry.to_api_format(reg)
      names = Enum.map(tools, & &1["name"])

      assert "fake_avail" in names
      assert "cond_tool" in names
      refute "unavailable_tool" in names
    end
  end
end
