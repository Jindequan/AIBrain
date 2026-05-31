defmodule AIBrain.Tool.Builtin.FileEditTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.FileEdit

  setup do
    dir = Path.join(System.tmp_dir!(), "aibrain_edit_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "edit.txt")
    File.write!(path, "hello world\nhello again\n")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, path: path, context: %{allowed_paths: [dir]}}
  end

  test "replaces unique occurrence", %{path: path, context: context} do
    assert {:ok, _} =
             FileEdit.execute(
               %{"path" => path, "old_string" => "hello again", "new_string" => "goodbye"},
               context
             )

    assert File.read!(path) =~ "goodbye"
    refute File.read!(path) =~ "hello again"
  end

  test "returns error when old_string not found", %{path: path, context: context} do
    assert {:error, msg} =
             FileEdit.execute(
               %{"path" => path, "old_string" => "NOTEXIST", "new_string" => "x"},
               context
             )

    assert msg =~ "not found"
  end

  test "returns error when old_string appears more than once", %{path: path, context: context} do
    assert {:error, msg} =
             FileEdit.execute(
               %{"path" => path, "old_string" => "hello", "new_string" => "hi"},
               context
             )

    assert msg =~ "multiple"
  end

  test "blocks edits outside the active workspace", %{path: path} do
    workspace = Path.join(System.tmp_dir!(), "aibrain_edit_ws_#{:rand.uniform(99999)}")
    File.mkdir_p!(workspace)

    assert {:error, {:sandbox_blocked, :workspace_write, msg}} =
             FileEdit.execute(
               %{"path" => path, "old_string" => "hello again", "new_string" => "blocked"},
               %{cwd: workspace}
             )

    assert msg =~ "outside the allowed workspace"
    refute File.read!(path) =~ "blocked"

    File.rm_rf!(workspace)
  end

  test "read_only? is false" do
    refute FileEdit.read_only?()
  end
end
