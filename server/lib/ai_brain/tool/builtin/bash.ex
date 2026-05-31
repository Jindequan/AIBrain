defmodule AIBrain.Tool.Builtin.Bash do
  @behaviour AIBrain.Tool.Behaviour

  alias AIBrain.Tool.{Error, Result}

  @default_timeout_ms 120_000
  @summary_head 20
  @summary_tail 20

  def name, do: "bash"
  def description, do: "Execute a shell command. Returns stdout. On error returns stderr."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "command" => %{"type" => "string", "description" => "The shell command to run"},
        "timeout" => %{"type" => "integer", "description" => "Timeout in ms (default 120000)"}
      },
      "required" => ["command"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :shell_exec

  def execute(%{"_raw" => raw_json} = _args, context) do
    # Handle raw JSON format
    case Jason.decode(raw_json) do
      {:ok, %{"command" => _cmd} = parsed} ->
        execute(parsed, context)

      {:ok, other} ->
        {:error,
         "Invalid _raw format: expected #{inspect(%{"command" => "..."})}, got #{inspect(other)}"}

      {:error, reason} ->
        {:error, "Failed to decode _raw JSON: #{inspect(reason)}"}
    end
  end

  def execute(%{"command" => cmd} = args, context) do
    # Sandbox check: block dangerous commands
    with :ok <- AIBrain.Tool.Sandbox.BashSandbox.check_command(cmd, context),
         :ok <- validate_cwd(context) do
      do_execute(cmd, args, context)
    end
  end

  defp validate_cwd(context) do
    cwd = context[:cwd] || File.cwd!()

    AIBrain.Tool.Sandbox.PathValidator.validate(cwd,
      operation: :read,
      cwd: context[:cwd],
      allowed_paths: context[:allowed_paths] || context[:workspace_roots]
    )
  end

  defp do_execute(cmd, args, context) do
    timeout = args["timeout"] || context[:timeout] || @default_timeout_ms
    cwd = context[:cwd] || File.cwd!()

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", cmd],
          stderr_to_stdout: true,
          cd: cwd,
          env: [{"HOME", System.get_env("HOME", "/tmp")}]
        )
      end)

    result =
      case Task.yield(task, timeout) do
        {:ok, value} -> {:ok, value}
        {:exit, reason} -> {:shutdown, reason}
        nil -> :timeout
      end

    case result do
      {:ok, {output, 0}} ->
        {:ok,
         %{
           content: output,
           metadata: %{command: cmd, exit_code: 0, cwd: cwd}
         }}

      {:ok, {output, exit_code}} ->
        {:error, Error.execution(output) |> with_command_meta(cmd, exit_code, cwd)}

      {:shutdown, _reason} ->
        {:error, Error.execution("Command exited abnormally: #{cmd}")}

      :timeout ->
        Task.shutdown(task, :brutal_kill)
        {:error, Error.timeout("Command timed out after #{timeout}ms", command: cmd)}
    end
  end

  def available?, do: true

  def summarize(output, _opts) do
    lines = String.split(output, "\n")
    total = length(lines)

    case Result.head_tail(lines, head: @summary_head, tail: @summary_tail) do
      {:full, all} ->
        Enum.join(all, "\n")

      {:split, head, tail, skipped} ->
        errors = Enum.filter(lines, &error_line?/1)

        error_section =
          if errors != [] do
            shown = Enum.take(errors, 5)

            "\n--- ERRORS (#{length(errors)} total, showing #{length(shown)}) ---\n" <>
              Enum.join(shown, "\n")
          else
            ""
          end

        "[#{total} lines, #{skipped} omitted]#{error_section}\n" <>
          "--- HEAD ---\n#{Enum.join(head, "\n")}\n" <>
          "--- TAIL ---\n#{Enum.join(tail, "\n")}\n" <>
          "[Full output saved to file]"
    end
  end

  defp error_line?(line) do
    l = String.downcase(line)

    String.contains?(l, "error") or String.contains?(l, "warning") or
      String.contains?(l, "failed") or String.contains?(l, "fatal")
  end

  defp with_command_meta(%Error{} = err, cmd, exit_code, cwd) do
    %{err | details: Map.merge(err.details, %{command: cmd, exit_code: exit_code, cwd: cwd})}
  end
end
