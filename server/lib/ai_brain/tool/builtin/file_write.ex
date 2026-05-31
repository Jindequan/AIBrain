defmodule AIBrain.Tool.Builtin.FileWrite do
  @behaviour AIBrain.Tool.Behaviour

  def name, do: "file_write"
  def description, do: "Write content to a file. Creates parent directories if needed."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string"},
        "content" => %{"type" => "string"}
      },
      "required" => ["path", "content"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :workspace_write

  def execute(%{"path" => path, "content" => content}, context) do
    path = resolve_path(path, context)

    with :ok <-
           AIBrain.Tool.Sandbox.PathValidator.validate(
             path,
             sandbox_opts(context, :workspace_write)
           ) do
      do_write(path, content)
    end
  end

  defp do_write(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok -> {:ok, "Wrote #{byte_size(content)} bytes to #{path}"}
      {:error, reason} -> {:error, "Write failed: #{:file.format_error(reason)}"}
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

  defp sandbox_opts(context, operation) do
    [
      operation: operation,
      cwd: context[:cwd],
      allowed_paths: context[:allowed_paths] || context[:workspace_roots]
    ]
  end
end
