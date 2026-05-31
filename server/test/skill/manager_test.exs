defmodule AIBrain.Skill.ManagerTest do
  use ExUnit.Case, async: false

  alias AIBrain.Skill.{Manager, Registry}

  setup do
    builtin_path = temp_dir!("builtin")
    data_dir = temp_dir!("data")
    user_path = Path.join(data_dir, "skills")
    File.mkdir_p!(user_path)
    name = Module.concat(__MODULE__, :"Registry#{System.unique_integer([:positive])}")
    start_supervised!({Registry, [name: name, builtin_path: builtin_path, user_path: user_path]})
    Process.put(:skill_registry, name)

    original_data_dir = Application.get_env(:ai_brain, :data_dir)
    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      Process.delete(:skill_registry)

      if original_data_dir do
        Application.put_env(:ai_brain, :data_dir, original_data_dir)
      else
        Application.delete_env(:ai_brain, :data_dir)
      end
    end)

    %{registry: name, user_path: user_path}
  end

  test "creates user skills", ctx do
    assert {:ok, skill} =
             Manager.create(%{
               "name" => "my-skill",
               "description" => "Helps with a specific workflow.",
               "body" => "# Workflow\n\nDo the work."
             })

    assert skill.name == "my-skill"
    assert File.exists?(Path.join([ctx.user_path, "my-skill", "SKILL.md"]))
  end

  test "imports a local skill directory" do
    source = temp_dir!("source")
    File.write!(Path.join(source, "SKILL.md"), """
    ---
    name: imported
    description: Imported skill.
    ---

    Body
    """)

    assert {:ok, skill} = Manager.import_path(source)
    assert skill.name == "imported"
    assert skill.origin == :user
  end

  test "rejects duplicate skill names" do
    attrs = %{"name" => "dup", "description" => "Duplicate.", "body" => "Body"}
    assert {:ok, _} = Manager.create(attrs)
    assert {:error, :already_exists} = Manager.create(attrs)
  end

  defp temp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "aibrain_skill_manager_#{prefix}_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
