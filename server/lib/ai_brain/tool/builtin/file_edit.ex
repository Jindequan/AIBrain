defmodule AIBrain.Tool.Builtin.FileEdit do
  @behaviour AIBrain.Tool.Behaviour

  def name, do: "file_edit"

  def description,
    do: "Replace a unique string in a file. Fails if old_string appears 0 or 2+ times."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string"},
        "old_string" => %{"type" => "string"},
        "new_string" => %{"type" => "string"}
      },
      "required" => ["path", "old_string", "new_string"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :workspace_write

  def execute(%{"path" => path, "old_string" => old, "new_string" => new}, context) do
    path = resolve_path(path, context)

    with :ok <-
           AIBrain.Tool.Sandbox.PathValidator.validate(
             path,
             sandbox_opts(context, :workspace_write)
           ) do
      do_edit(path, old, new)
    end
  end

  defp do_edit(path, old, new) do
    with {:ok, content} <- File.read(path) do
      count = count_occurrences(content, old)

      cond do
        count == 0 ->
          {:error, "old_string not found in #{path}"}

        count > 1 ->
          {:error, "old_string found multiple times (#{count}) in #{path} — make it unique"}

        true ->
          updated = String.replace(content, old, new, global: false)

          case File.write(path, updated) do
            :ok -> {:ok, "Replaced 1 occurrence in #{path}"}
            {:error, r} -> {:error, "Write failed: #{:file.format_error(r)}"}
          end
      end
    else
      {:error, reason} -> {:error, "Cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp count_occurrences(string, substr) do
    string |> String.split(substr) |> length() |> Kernel.-(1)
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
