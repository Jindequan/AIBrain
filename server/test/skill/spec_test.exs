defmodule AIBrain.Skill.SpecTest do
  use ExUnit.Case, async: true

  alias AIBrain.Skill.Spec

  test "parses Codex-style SKILL.md" do
    root = temp_dir!()
    path = Path.join(root, "SKILL.md")

    File.mkdir_p!(Path.join(root, "references"))
    File.write!(Path.join(root, "references/guide.md"), "details")

    File.write!(path, """
    ---
    name: code-review
    description: Review code for bugs and maintainability.
    metadata:
      short-description: Review code
    ---

    # Code Review

    Find concrete issues first.
    """)

    assert {:ok, %Spec{} = spec} = Spec.parse(path)
    assert spec.name == "code-review"
    assert spec.description == "Review code for bugs and maintainability."
    assert spec.body =~ "Find concrete issues"
    assert spec.metadata["short-description"] == "Review code"
    assert spec.path == path
    assert spec.root_path == root
    assert spec.resources.references == [Path.join(root, "references/guide.md")]
  end

  test "requires SKILL.md filename" do
    path = Path.join(temp_dir!(), "skill.md")
    File.write!(path, "---\nname: bad\ndescription: Bad\n---\nBody")

    assert {:error, reason} = Spec.parse(path)
    assert reason =~ "SKILL.md"
  end

  test "requires name and description" do
    path = Path.join(temp_dir!(), "SKILL.md")
    File.write!(path, "---\nname: missing-description\n---\nBody")

    assert {:error, reason} = Spec.parse(path)
    assert reason =~ "description"
  end

  test "validates lowercase skill names" do
    assert Spec.validate_name("good-skill_1") == :ok
    assert {:error, _} = Spec.validate_name("BadSkill")
    assert {:error, _} = Spec.validate_name("../bad")
  end

  test "renders canonical SKILL.md" do
    spec = %Spec{
      name: "research",
      description: "Research things.",
      body: "# Research\n\nVerify claims.",
      path: "",
      root_path: "",
      origin: :user,
      metadata: %{"short-description" => "Research"}
    }

    rendered = Spec.render(spec)
    assert rendered =~ "name: research"
    assert rendered =~ "description: Research things."
    assert rendered =~ "metadata:"
    assert rendered =~ "# Research"
  end

  defp temp_dir! do
    path = Path.join(System.tmp_dir!(), "aibrain_skill_spec_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
