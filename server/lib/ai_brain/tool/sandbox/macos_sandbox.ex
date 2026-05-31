defmodule AIBrain.Tool.Sandbox.MacOSSandbox do
  @moduledoc """
  macOS native sandbox using sandbox-exec (built into macOS, no install needed).

  Replaces firejail for macOS users. sandbox-exec uses Apple's Seatbelt
  sandbox framework with a Scheme-like policy language.

  The default profile:
    - Denies all operations by default
    - Allows read from anywhere (needed for dev tools)
    - Allows write only to the working directory and /tmp
    - Allows network outbound
    - Allows process execution of common shells
  """

  require Logger

  @sandbox_profile """
  (version 1)
  (deny default)
  (allow process-exec
    (literal "/bin/sh")
    (literal "/bin/bash")
    (literal "/bin/zsh")
    (literal "/usr/bin/env")
    (literal "/usr/bin/python3")
    (literal "/usr/bin/ruby")
    (literal "/opt/homebrew/bin/"))
  (allow sysctl-read)
  (allow file-read*)
  (allow file-write*
    (subpath "/tmp")
    (subpath "/private/tmp")
    (subpath (param "WORK_DIR")))
  (allow process-fork)
  (deny network*)
  (allow network-outbound
    (remote ip "*:*"))
  """

  @doc """
  Run a command inside macOS sandbox-exec.

  Options:
    - :cd — working directory (required)
    - :deny_network — if true, removes network-outbound from profile

  Returns {:ok, output} or {:error, reason}.
  """
  def run(command, opts \\ []) do
    working_dir = Keyword.get(opts, :cd, System.tmp_dir!())
    deny_network = Keyword.get(opts, :deny_network, false)

    profile = build_profile(working_dir, deny_network)
    profile_path = write_temp_profile(profile)

    try do
      result =
        System.cmd("sandbox-exec", ["-f", profile_path, "sh", "-c", command],
          cd: working_dir,
          stderr_to_stdout: true
        )

      case result do
        {output, 0} ->
          {:ok, String.trim(output)}

        {output, code} ->
          {:error, "sandbox-exec exit #{code}: #{String.trim(output)}"}
      end
    rescue
      e in ErlangError ->
        {:error, "sandbox-exec failed: #{Exception.message(e)}"}
    after
      File.rm(profile_path)
    end
  end

  @doc """
  Returns true if sandbox-exec is available on this system.
  """
  def available? do
    case System.cmd("which", ["sandbox-exec"]) do
      {path, 0} -> String.trim(path) != "" && String.contains?(path, "sandbox-exec")
      _ -> false
    end
  end

  @doc """
  Returns true if running on macOS.
  """
  def macos? do
    :os.type() == {:unix, :darwin}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp build_profile(working_dir, deny_network) do
    profile =
      String.replace(@sandbox_profile, "(param \"WORK_DIR\")", "\"#{escape_param(working_dir)}\"")

    if deny_network do
      profile
      |> String.replace("(allow network-outbound\n    (remote ip \"*:*\"))", "")
    else
      profile
    end
  end

  defp escape_param(value) do
    value
    |> String.replace("\"", "")
    |> String.replace(~r/[\r\n]/, " ")
  end

  defp write_temp_profile(profile) do
    path =
      Path.join(System.tmp_dir!(), "aibrain-sandbox-#{System.unique_integer([:positive])}.sb")

    File.write!(path, profile)
    path
  end
end
