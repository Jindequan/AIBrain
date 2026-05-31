defmodule AIBrain.Tool.Builtin.Grep do
  @behaviour AIBrain.Tool.Behaviour
  require Logger

  def name, do: "grep"
  def description, do: "Search for a regex pattern in files."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "pattern" => %{"type" => "string"},
        "path" => %{"type" => "string", "description" => "Directory or file to search"},
        "glob" => %{"type" => "string", "description" => "File filter e.g. *.ex"}
      },
      "required" => ["pattern", "path"]
    }
  end

  def read_only?, do: true

  def execute(%{"pattern" => pattern, "path" => path} = args, context) do
    path = resolve_path(path, context)
    glob = args["glob"]

    case Regex.compile(pattern, [:caseless]) do
      {:error, {reason, _pos}} ->
        {:error, "Invalid regex pattern: #{reason}"}

      {:ok, _} ->
        result = try_rg(pattern, path, glob) || fallback_search(pattern, path, glob)
        if result == "", do: {:ok, "No matches found."}, else: {:ok, result}
    end
  end

  defp try_rg(pattern, path, glob) do
    args = ["--line-number", "--color=never"]
    args = if glob, do: args ++ ["--glob", glob], else: args
    args = args ++ [pattern, path]

    case System.cmd("rg", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, 1} when output == "" -> ""
      _ -> nil
    end
  rescue
    e ->
      Logger.error("AIBrain.Tool.Builtin.Grep.try_rg failed: #{Exception.message(e)}")
      nil
  end

  defp fallback_search(pattern, path, glob) do
    {:ok, regex} = Regex.compile(pattern, [:caseless])
    files = list_files(path, glob)

    files
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, content} ->
          content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _} -> Regex.match?(regex, line) end)
          |> Enum.map(fn {line, n} -> "#{file}:#{n}: #{line}" end)

        _ ->
          []
      end
    end)
    |> Enum.join("\n")
  end

  defp list_files(path, nil) do
    if File.dir?(path) do
      Path.wildcard(Path.join(path, "**/*")) |> Enum.filter(&File.regular?/1)
    else
      [path]
    end
  end

  defp list_files(path, glob) do
    Path.wildcard(Path.join(path, "**/" <> glob))
  end

  defp resolve_path(path, context) do
    cwd = context[:cwd]

    if cwd && Path.type(path) not in [:absolute, :vms] do
      Path.expand(path, cwd)
    else
      path
    end
  end
end
