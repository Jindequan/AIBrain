defmodule AIBrain.Tool.Builtin.FileReadTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.FileRead

  setup do
    dir = Path.join(System.tmp_dir!(), "aibrain_read_#{:rand.uniform(99999)}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "test.txt")
    content = Enum.map(1..10, &"Line #{&1}") |> Enum.join("\n")
    File.write!(path, content)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, path: path, content: content, context: %{allowed_paths: [dir]}}
  end

  test "reads full file", %{path: path, context: context} do
    assert {:ok, result} = FileRead.execute(%{"path" => path}, context)
    assert %{"content" => content, "metadata" => metadata} = result
    assert content =~ "Line 1"
    assert content =~ "Line 10"
    assert metadata["total_lines"] == 10
  end

  test "reads with offset and limit", %{path: path, context: context} do
    assert {:ok, result} =
             FileRead.execute(%{"path" => path, "offset" => 3, "limit" => 2}, context)

    assert %{"content" => content, "metadata" => metadata} = result
    assert content =~ "Line 3"
    assert content =~ "Line 4"
    refute content =~ "Line 5"
    assert metadata["has_more"] == true
    assert metadata["next_offset"] == 5
  end

  test "returns error for nonexistent file" do
    assert {:error, _} = FileRead.execute(%{"path" => "/nonexistent/file.txt"}, %{})
  end

  test "read_only? is true" do
    assert FileRead.read_only?()
  end
end
