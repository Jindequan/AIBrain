defmodule AIBrain.Tool.Builtin.GrepTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Grep

  setup do
    dir = Path.join(System.tmp_dir!(), "aibrain_grep_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "code.ex"), "def hello, do: :world\ndef goodbye, do: :earth\n")
    File.write!(Path.join(dir, "other.txt"), "hello from text\n")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  test "finds pattern in files", %{dir: dir} do
    {:ok, result} = Grep.execute(%{"pattern" => "hello", "path" => dir}, %{})
    assert result =~ "hello"
  end

  test "returns no matches message when nothing found", %{dir: dir} do
    {:ok, result} = Grep.execute(%{"pattern" => "XXXXNOTFOUND", "path" => dir}, %{})
    assert result =~ "No matches"
  end

  test "supports glob file filter", %{dir: dir} do
    {:ok, result} = Grep.execute(%{"pattern" => "hello", "path" => dir, "glob" => "*.ex"}, %{})
    assert result =~ "code.ex"
    refute result =~ "other.txt"
  end

  test "read_only? is true" do
    assert Grep.read_only?()
  end
end
