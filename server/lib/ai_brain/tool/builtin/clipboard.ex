defmodule AIBrain.Tool.Builtin.Clipboard do
  @behaviour AIBrain.Tool.Behaviour

  @impl true
  def name, do: "clipboard"

  @impl true
  def description, do: "Read from or write to the system clipboard"

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["read", "write"],
          "description" => "Read clipboard contents or write to it"
        },
        "content" => %{
          "type" => "string",
          "description" => "Content to write to clipboard (required for write action)"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def read_only?, do: false

  @impl true
  def risk_category, do: :workspace_write

  @impl true
  def available? do
    case :os.type() do
      {:unix, :darwin} -> System.find_executable("pbpaste") != nil
      {:unix, :linux} -> System.find_executable("xclip") != nil
      {:win32, _} -> System.find_executable("powershell") != nil
    end
  end

  @impl true
  def execute(%{"action" => "read"}, _context) do
    read_fn = read_command()

    case System.cmd(read_fn.cmd, read_fn.args) do
      {output, 0} ->
        trimmed = String.trim(output)

        if trimmed == "" do
          {:ok, "(clipboard is empty)"}
        else
          {:ok, trimmed}
        end

      {error, code} ->
        {:error, "Failed to read clipboard (exit #{code}): #{String.trim(error)}"}
    end
  end

  def execute(%{"action" => "write", "content" => content}, _context) do
    write_fn = write_command()

    case System.cmd(write_fn.cmd, write_fn.args, input: content) do
      {"", 0} ->
        byte_count = byte_size(content)
        {:ok, "Clipboard updated (#{byte_count} bytes)"}

      {error, code} ->
        {:error, "Failed to write clipboard (exit #{code}): #{String.trim(error)}"}
    end
  end

  def execute(%{"action" => "write"}, _context) do
    {:error, "Missing required field: content (for write action)"}
  end

  def execute(%{"action" => action}, _context) do
    {:error, "Unknown action: #{action}. Use 'read' or 'write'."}
  end

  def execute(_params, _context) do
    {:error, "Missing required field: action (read or write)"}
  end

  # ── OS-specific commands ────────────────────────────────────────

  defp read_command do
    case :os.type() do
      {:unix, :darwin} -> %{cmd: "pbpaste", args: []}
      {:unix, :linux} -> %{cmd: "xclip", args: ["-selection", "clipboard", "-o"]}
      {:win32, _} -> %{cmd: "powershell", args: ["-command", "Get-Clipboard"]}
    end
  end

  defp write_command do
    case :os.type() do
      {:unix, :darwin} -> %{cmd: "pbcopy", args: []}
      {:unix, :linux} -> %{cmd: "xclip", args: ["-selection", "clipboard"]}
      {:win32, _} -> %{cmd: "powershell", args: ["-command", "Set-Clipboard -Value $input"]}
    end
  end
end
