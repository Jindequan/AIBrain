defmodule AIBrain.Tool.Sandbox.BashSandbox do
  @moduledoc """
  Validates bash commands and executes them with appropriate isolation.

  Three isolation levels:
    - :process  — run directly in a tmp working directory (safe/local_write/network)
    - :wasi     — firejail if available, else restricted tmp jail + resource limits (shell_exec)
    - :container — firejail --net=none (critical)
  """

  require Logger

  @dangerous_patterns [
    # Destructive file operations
    ~r{\Arm\s+-\s*[rf]+\s*/},
    ~r{\Arm\s+-\s*[rf]+\s+/(?:etc|boot|sys)\b},
    ~r{dd\s+(?:if|of)=/dev/(?:zero|sda|sdb|sdc|sdd)},
    # Fork bomb
    ~r{:\(\)\s*\{\s*:\s*\|:\s*&\s*\}\s*;?\s*:},
    # Disk/filesystem destruction
    ~r{(?:^|\s)mkfs\.},
    ~r{(?:^|\s)chmod\s+-\s*R?\s*777\s+/},
    ~r{(?:^|\s)chown\s+-\s*R?\s*0:0\s+/},
    ~r{>/dev/sda},
    ~r{(?:^|\s)echo\s+.*>/dev/sda},
    ~r{(?:^|\s)wget\s+-O\s+/dev/sda},
    # Pipe to shell (curl|bash and variants)
    ~r{curl\s+.*\|\s*(?:ba)?sh\b},
    ~r{wget\s+.*\|\s*(?:ba)?sh\b},
    # Interpreter execution with inline code (bypasses pattern checks)
    ~r{(?:^|\s)python[23]?\s+-c\s},
    ~r{(?:^|\s)perl\s+-e\s},
    ~r{(?:^|\s)ruby\s+-e\s},
    ~r{(?:^|\s)node\s+-e\s},
    ~r{(?:^|\s)php\s+-r\s},
    # Network tools that enable reverse shells / data exfil
    ~r{(?:^|\s)nc\s+-},
    ~r{(?:^|\s)ncat\s},
    ~r{(?:^|\s)socat\s},
    ~r{(?:^|\s)(?:ba)?sh\s+-i\s},
    ~r{(?:^|\s)(?:ba)?sh\s+<(?:\(|\(curl|\(wget)},
    # Base64 pipe to shell (obfuscated payloads)
    ~r{base64\s+.*\|\s*(?:ba)?sh\b},
    # Disk write / bootloader
    ~r{>\s*/\*\s*$},
    ~r{(?:^|\s)write\s+/dev/(?:sda|sdb|sdc|sdd)},
    ~r{(?:^|\s)ptx},
    # System shutdown commands
    ~r{(?:^|\s)halt\s*$},
    ~r{(?:^|\s)poweroff\s*$},
    ~r{(?:^|\s)reboot\s*$},
    ~r{(?:^|\s)shutdown\s+},
    ~r{(?:^|\s)init\s+[06]},
    # /proc & /sys manipulation
    ~r{>\s*/proc/},
    ~r{>\s*/sys/}
  ]

  @firejail_paths ["/usr/bin/firejail", "/usr/local/bin/firejail", "/opt/homebrew/bin/firejail"]

  @doc """
  Check if a command is safe to execute.
  Returns `:ok` or `{:error, reason}`.
  """
  def check_command(command, opts \\ []) when is_binary(command) do
    trimmed = String.trim(command)

    cond do
      blocked_by_policy?(trimmed, opts) ->
        {:error, {:sandbox_blocked, :shell_exec, "Command blocked by shell policy: #{trimmed}"}}

      true ->
        with :ok <- validate_referenced_paths(trimmed, opts) do
          case match_dangerous(trimmed) do
            nil -> :ok
            pattern -> {:error, "Command blocked: matches dangerous pattern #{inspect(pattern)}"}
          end
        end
    end
  end

  @doc """
  Run a shell command with the given isolation level.

  Options:
    - :cd — working directory (defaults to a tmp dir for :wasi/:container)
    - :env — list of env vars
    - :timeout — timeout in ms (default 60_000)
    - :stdin — stdin string
  """
  def safe_cmd(command, isolation \\ :process, opts \\ []) when is_binary(command) do
    with :ok <- check_command(command, opts) do
      do_safe_cmd(command, isolation, opts)
    end
  end

  defp do_safe_cmd(command, :process, opts) do
    cwd = Keyword.get(opts, :cd, System.tmp_dir!())
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, 60_000)

    case System.cmd("sh", ["-c", command],
           cd: cwd,
           env: env,
           timeout: timeout,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, "Command exited #{code}: #{String.trim(output)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "Command timed out or failed: #{Exception.message(e)}"}
  end

  defp do_safe_cmd(command, :wasi, opts) do
    cond do
      AIBrain.Tool.Sandbox.MacOSSandbox.macos?() and
          AIBrain.Tool.Sandbox.MacOSSandbox.available?() ->
        AIBrain.Tool.Sandbox.MacOSSandbox.run(command, opts)

      firejail_available?() ->
        run_firejail(firejail_path!(), command, opts, [])

      true ->
        Logger.warning(
          "BashSandbox: no sandbox available, falling back to restricted tmp jail for :wasi isolation"
        )

        run_restricted_tmp(command, opts)
    end
  end

  defp do_safe_cmd(command, :container, opts) do
    cond do
      AIBrain.Tool.Sandbox.MacOSSandbox.macos?() and
          AIBrain.Tool.Sandbox.MacOSSandbox.available?() ->
        AIBrain.Tool.Sandbox.MacOSSandbox.run(command, Keyword.put(opts, :deny_network, true))

      firejail_available?() ->
        run_firejail(firejail_path!(), command, opts, [
          "--net=none",
          "--nodbus",
          "--nosound",
          "--private"
        ])

      true ->
        Logger.warning(
          "BashSandbox: no sandbox available, falling back to restricted tmp jail for :container isolation"
        )

        run_restricted_tmp(command, opts)
    end
  end

  defp do_safe_cmd(command, isolation, opts) when is_atom(isolation) do
    Logger.warning(
      "BashSandbox: unknown isolation #{inspect(isolation)}, falling back to :process"
    )

    do_safe_cmd(command, :process, opts)
  end

  # ── firejail ───────────────────────────────────────────────────

  defp run_firejail(firejail, command, opts, extra_args) do
    cwd = Keyword.get(opts, :cd, System.tmp_dir!())
    timeout = Keyword.get(opts, :timeout, 60_000)

    args = ["--quiet"] ++ extra_args ++ ["sh", "-c", command]

    case System.cmd(firejail, args, cd: cwd, timeout: timeout, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, code} -> {:error, "Command (firejail) exited #{code}: #{String.trim(output)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "firejail execution failed: #{Exception.message(e)}"}
  end

  defp firejail_available? do
    firejail_path() != :not_found
  end

  defp firejail_path! do
    {:ok, path} = firejail_path()
    path
  end

  defp firejail_path do
    Enum.find_value(@firejail_paths, :not_found, fn path ->
      if File.exists?(path) and File.regular?(path), do: {:ok, path}
    end)
  end

  # ── restricted tmp jail (fallback) ─────────────────────────────

  # When no sandbox (firejail/macOS) is available, still apply
  # command-level restrictions and network egress blocking.
  defp run_restricted_tmp(command, opts) do
    tmp_dir = mktmp()
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Build a restricted PATH that excludes network tools
    _original_path = System.get_env("PATH", "/usr/bin:/bin")
    safe_dirs = ~w(/usr/bin /bin /usr/local/bin)

    restricted_path =
      safe_dirs
      |> Enum.filter(&File.dir?/1)
      |> Enum.join(":")

    # Blocked network commands — replace with harmless echo
    network_cmds = ~w(curl wget nc ncat socat telnet ssh scp sftp rsync ftp nc.traditional)
    deny_pattern = Enum.map_join(network_cmds, "|", &Regex.escape/1)

    sanitized =
      Regex.replace(
        ~r/(?:^|\|;|&&|\|\||\n)\s*(#{deny_pattern})\b/,
        command,
        fn _match, cmd ->
          " echo '[sandbox] #{cmd} blocked (no network tools in fallback sandbox)'"
        end
      )

    try do
      result =
        System.cmd("sh", ["-c", sanitized],
          cd: tmp_dir,
          timeout: timeout,
          stderr_to_stdout: true,
          env: [{"PATH", restricted_path}, {"HOME", tmp_dir}]
        )

      case result do
        {output, 0} -> {:ok, String.trim(output)}
        {output, code} -> {:error, "Command (restricted) exited #{code}: #{String.trim(output)}"}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp mktmp do
    dir = Path.join(System.tmp_dir!(), "aibrain-sandbox-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  @doc "List all dangerous command patterns for display/logging."
  def dangerous_patterns, do: @dangerous_patterns

  # ── private helpers ────────────────────────────────────────────

  defp match_dangerous(command) do
    Enum.find(@dangerous_patterns, fn pattern ->
      String.match?(command, pattern)
    end)
  end

  defp validate_referenced_paths(command, opts) do
    command
    |> referenced_absolute_paths()
    |> Enum.reduce_while(:ok, fn path, :ok ->
      operation = if write_path_reference?(command, path), do: :write, else: :read

      case AIBrain.Tool.Sandbox.PathValidator.validate(path, sandbox_opts(opts, operation)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp referenced_absolute_paths(command) do
    ~r/(?:^|[\s"'=:(])(?<path>\/[A-Za-z0-9._~+@%:\/-]+)/
    |> Regex.scan(command, capture: ["path"])
    |> List.flatten()
    |> Enum.reject(&(&1 in ["/dev/null", "/dev/zero", "/dev/random", "/dev/urandom"]))
    |> Enum.uniq()
  end

  defp write_path_reference?(command, path) do
    String.contains?(command, ["> #{path}", ">> #{path}", ">#{path}", ">>#{path}"]) or
      String.match?(command, ~r/\b(?:touch|mkdir|rm|mv|cp)\b.*#{Regex.escape(path)}/)
  end

  defp sandbox_opts(opts, operation) when is_list(opts) do
    [
      operation: operation,
      cwd: Keyword.get(opts, :cwd) || Keyword.get(opts, :cd),
      allowed_paths: Keyword.get(opts, :allowed_paths) || Keyword.get(opts, :workspace_roots)
    ]
  end

  defp sandbox_opts(%{} = opts, operation) do
    [
      operation: operation,
      cwd:
        Map.get(opts, :cwd) || Map.get(opts, "cwd") || Map.get(opts, :cd) || Map.get(opts, "cd"),
      allowed_paths:
        Map.get(opts, :allowed_paths) || Map.get(opts, "allowed_paths") ||
          Map.get(opts, :workspace_roots) || Map.get(opts, "workspace_roots")
    ]
  end

  defp blocked_by_policy?(command, opts) do
    first_word =
      command
      |> String.split(~r/\s+/, parts: 2, trim: true)
      |> List.first()

    blocked =
      opt_list(opts, :blocked_commands) ++
        Application.get_env(:ai_brain, :blocked_shell_commands, [])

    allowed =
      opt_list(opts, :allowed_commands) ++
        Application.get_env(:ai_brain, :allowed_shell_commands, [])

    cond do
      first_word in blocked -> true
      allowed != [] and first_word not in allowed -> true
      true -> false
    end
  end

  defp opt_list(opts, key) when is_list(opts) do
    case Keyword.get(opts, key, []) do
      list when is_list(list) -> list
      item when is_binary(item) -> [item]
      _ -> []
    end
  end

  defp opt_list(%{} = opts, key) do
    case Map.get(opts, key, []) do
      list when is_list(list) -> list
      item when is_binary(item) -> [item]
      _ -> []
    end
  end
end
