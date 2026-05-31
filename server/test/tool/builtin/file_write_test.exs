defmodule AIBrain.Tool.Builtin.FileWriteTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.FileWrite

  setup do
    dir = Path.join(System.tmp_dir!(), "aibrain_write_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir, context: %{allowed_paths: [dir]}}
  end

  test "writes content to file", %{dir: dir, context: context} do
    path = Path.join(dir, "out.txt")
    assert {:ok, _} = FileWrite.execute(%{"path" => path, "content" => "hello"}, context)
    assert File.read!(path) == "hello"
  end

  test "creates parent directories automatically", %{dir: dir, context: context} do
    path = Path.join([dir, "nested", "deep", "file.txt"])
    assert {:ok, _} = FileWrite.execute(%{"path" => path, "content" => "deep"}, context)
    assert File.read!(path) == "deep"
  end

  test "blocks writes outside the active workspace", %{dir: dir} do
    outside = Path.join(System.tmp_dir!(), "aibrain_outside_#{:rand.uniform(99999)}.txt")

    assert {:error, {:sandbox_blocked, :workspace_write, msg}} =
             FileWrite.execute(%{"path" => outside, "content" => "nope"}, %{cwd: dir})

    assert msg =~ "outside the allowed workspace"
    refute File.exists?(outside)
  end

  test "read_only? is false" do
    refute FileWrite.read_only?()
  end
end
