defmodule AIBrain.Tool.Builtin.Glob do
  @behaviour AIBrain.Tool.Behaviour

  def name, do: "glob"
  def description, do: "Find files matching a glob pattern."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "pattern" => %{"type" => "string", "description" => "e.g. lib/**/*.ex"}
      },
      "required" => ["pattern"]
    }
  end

  def read_only?, do: true

  def execute(%{"pattern" => pattern}, context) do
    pattern = resolve_path(pattern, context)
    matches = Path.wildcard(pattern) |> Enum.sort()

    case matches do
      [] -> {:ok, "No files matched."}
      _ -> {:ok, Enum.join(matches, "\n")}
    end
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
