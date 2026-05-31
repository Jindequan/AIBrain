defmodule AIBrain.Tool.Builtin.FileRead do
  @behaviour AIBrain.Tool.Behaviour

  alias AIBrain.Tool.Result

  @max_read_lines Application.compile_env(:ai_brain, :max_read_lines, 500)

  def name, do: "file_read"

  def description do
    "Read a file. By default reads up to #{@max_read_lines} lines. Supports pagination with offset (1-based line number) and limit."
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string", "description" => "File path to read"},
        "offset" => %{"type" => "integer", "description" => "Start line (1-based), defaults to 1"},
        "limit" => %{
          "type" => "integer",
          "description" => "Max lines to return, defaults to #{@max_read_lines}"
        }
      },
      "required" => ["path"]
    }
  end

  def read_only?, do: true

  def execute(%{"path" => path} = args, context) do
    path = resolve_path(path, context)

    with :ok <- AIBrain.Tool.Sandbox.PathValidator.validate(path, sandbox_opts(context, :read)) do
      do_read(path, args)
    end
  end

  defp do_read(path, args) do
    case File.read(path) do
      {:error, reason} ->
        {:error, "Cannot read #{path}: #{:file.format_error(reason)}"}

      {:ok, content} ->
        lines = String.split(content, "\n")
        total_lines = length(lines)

        offset = max((args["offset"] || 1) - 1, 0)
        limit = args["limit"] || @max_read_lines

        # Read the requested lines
        result_lines =
          lines
          |> Enum.drop(offset)
          |> Enum.take(limit)

        has_more = offset + length(result_lines) < total_lines
        next_offset = if has_more, do: offset + length(result_lines) + 1, else: nil

        # Format with line numbers
        formatted =
          result_lines
          |> Enum.with_index(offset + 1)
          |> Enum.map_join("\n", fn {line, n} -> "#{n}\t#{line}" end)

        metadata = %{
          "total_lines" => total_lines,
          "returned_lines" => length(result_lines),
          "has_more" => has_more
        }

        metadata =
          if next_offset, do: Map.put(metadata, "next_offset", next_offset), else: metadata

        {:ok,
         %{
           "content" => formatted,
           "metadata" => metadata
         }}
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

  def summarize(output, _opts) do
    lines = String.split(output, "\n")

    case Result.head_tail(lines) do
      {:full, all} ->
        Enum.join(all, "\n")

      {:split, head, tail, skipped} ->
        "#{Enum.join(head, "\n")}\n... #{skipped} lines omitted ...\n#{Enum.join(tail, "\n")}\n[Full output saved to file]"
    end
  end
end
