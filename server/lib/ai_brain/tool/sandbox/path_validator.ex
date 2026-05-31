defmodule AIBrain.Tool.Sandbox.PathValidator do
  @moduledoc """
  Validates file paths against allowed/blocked patterns.

  Blocks access to sensitive system files while allowing general filesystem
  access for personal assistant tasks.
  """

  @sensitive_patterns [
    # SSH keys
    ~r{(/|\\|\A)\.ssh(/|\\|\z)},
    # GPG keys
    ~r{(/|\\|\A)\.gnupg(/|\\|\z)},
    # System password files
    ~r{(/|\\|\A)etc/shadow(/|\\|\z)},
    ~r{(/|\\|\A)etc/sudoers(:?\.d)?(/|\\|\z)},
    ~r{(/|\\|\A)etc/passwd(/|\\|\z)},
    # Keychain / macOS secrets
    ~r{(/|\\|\A)Library/Keychains(/|\\|\z)},
    # Known credential files
    ~r{config/credentials\.yml\.enc\z},
    ~r{\.env\z},
    ~r{\.pem\z},
    ~r{id_rsa\z},
    ~r{id_ed25519\z},
    # Docker socket
    ~r{(/|\\|\A)var/run/docker\.sock\z},
    # /dev files (except safe ones)
    ~r{\A/dev/(?!null|zero|random|urandom|fd/)[^/]+}
  ]

  @doc """
  Validate that a path is safe to read/write.

  Returns `:ok` or `{:error, reason}`.
  """
  def validate(path, opts \\ []) do
    expanded = Path.expand(path)

    with :ok <- check_sensitive(expanded),
         :ok <- check_workspace(expanded, opts) do
      :ok
    end
  end

  defp check_sensitive(path) do
    matching =
      Enum.find(@sensitive_patterns, fn pattern ->
        String.match?(path, pattern)
      end)

    case matching do
      nil ->
        :ok

      pattern ->
        {:error, "Access denied: path matches sensitive pattern #{inspect(pattern)}: #{path}"}
    end
  end

  @doc "List all sensitive path patterns for display/logging."
  def sensitive_patterns, do: @sensitive_patterns

  defp check_workspace(path, opts) do
    operation = Keyword.get(opts, :operation, :read)

    cond do
      operation in [:write, :workspace_write] ->
        roots = allowed_roots(opts)

        if roots == [] or Enum.any?(roots, &inside_root?(path, &1)) do
          :ok
        else
          {:error,
           {:sandbox_blocked, :workspace_write,
            "Writes outside the allowed workspace are blocked. Path: #{path}"}}
        end

      operation == :read ->
        roots = allowed_roots(opts)

        if roots == [] or Enum.any?(roots, &inside_root?(path, &1)) do
          :ok
        else
          {:error,
           {:sandbox_blocked, :workspace_read,
            "Reads outside the allowed workspace are blocked. Path: #{path}"}}
        end

      true ->
        :ok
    end
  end

  defp allowed_roots(opts) do
    configured_roots =
      Keyword.get(opts, :allowed_paths) ||
        Keyword.get(opts, :workspace_roots) ||
        Application.get_env(:ai_brain, :allowed_workspace_roots, [])

    roots =
      case configured_roots do
        roots when is_list(roots) -> roots
        root when is_binary(root) -> [root]
        _ -> []
      end

    cwd = Keyword.get(opts, :cwd)
    roots = if is_binary(cwd), do: [cwd | roots], else: roots
    roots = roots ++ default_allowed_roots()

    roots
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp default_allowed_roots do
    workspace = Application.get_env(:ai_brain, :workspace_path)

    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    [System.user_home!(), workspace, data_dir]
    |> Enum.filter(&is_binary/1)
  end

  defp inside_root?(path, root) do
    path = Path.expand(path)
    root = Path.expand(root)
    root == "/" or path == root or String.starts_with?(path, root <> "/")
  end
end
