defmodule AIBrain.Tool.Builtin.GlobTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Glob

  setup do
    dir = Path.join(System.tmp_dir!(), "aibrain_glob_#{:rand.uniform(99999)}")
    File.mkdir_p!(Path.join(dir, "sub"))
    File.write!(Path.join(dir, "a.txt"), "a")
    File.write!(Path.join(dir, "b.ex"), "b")
    File.write!(Path.join([dir, "sub", "c.txt"]), "c")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "matches files by extension", %{dir: dir} do
    {:ok, result} = Glob.execute(%{"pattern" => "#{dir}/**/*.txt"}, %{})
    assert result =~ "a.txt"
    assert result =~ "c.txt"
    refute result =~ "b.ex"
  end

  test "returns empty result when no match", %{dir: dir} do
    {:ok, result} = Glob.execute(%{"pattern" => "#{dir}/**/*.xyz"}, %{})
    assert result == "No files matched."
  end

  test "read_only? is true" do
    assert Glob.read_only?()
  end
end
