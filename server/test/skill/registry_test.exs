defmodule AIBrain.Skill.RegistryTest do
  use ExUnit.Case, async: true

  alias AIBrain.Skill.Registry

  setup do
    builtin_path = temp_dir!("builtin")
    user_path = temp_dir!("user")
    name = Module.concat(__MODULE__, :"Registry#{System.unique_integer([:positive])}")
    start_supervised!({Registry, [name: name, builtin_path: builtin_path, user_path: user_path]})
    %{registry: name, builtin_path: builtin_path, user_path: user_path}
  end

  test "scans Codex-style built-in and user skills", ctx do
    write_skill!(ctx.builtin_path, "research", "Research", "Builtin body")
    write_skill!(ctx.user_path, "custom", "Custom", "User body")

    Registry.rescan(ctx.registry)

    assert {:ok, research} = Registry.get(ctx.registry, "research")
    assert research.origin == :builtin
    assert research.body =~ "Builtin"

    assert {:ok, custom} = Registry.get(ctx.registry, "custom")
    assert custom.origin == :user
  end

  test "user skill overrides built-in skill with same name", ctx do
    write_skill!(ctx.builtin_path, "research", "Builtin research", "Builtin body")
    write_skill!(ctx.user_path, "research", "User research", "User body")

    Registry.rescan(ctx.registry)

    assert {:ok, skill} = Registry.get(ctx.registry, "research")
    assert skill.origin == :user
    assert skill.description == "User research"
  end

  test "list_active filters paused skills", ctx do
    write_skill!(ctx.user_path, "active", "Active", "Body")
    write_skill!(ctx.user_path, "paused", "Paused", "Body", status: "paused")

    Registry.rescan(ctx.registry)

    names = ctx.registry |> Registry.list_active() |> Enum.map(& &1.name)
    assert names == ["active"]
  end

  test "catalog returns compact routing metadata", ctx do
    write_skill!(ctx.user_path, "coding", "Code work", "Body")
    Registry.rescan(ctx.registry)

    assert [%{name: "coding", description: "Code work"}] = Registry.catalog(ctx.registry)
  end

  defp write_skill!(root, name, description, body, opts \\ []) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    status = Keyword.get(opts, :status, "active")

    File.write!(Path.join(dir, "SKILL.md"), """
    ---
    name: #{name}
    description: #{description}
    status: #{status}
    ---

    #{body}
    """)
  end

  defp temp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "aibrain_skill_#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
