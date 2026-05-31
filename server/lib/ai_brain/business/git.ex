defmodule AIBrain.Business.Git do
  @moduledoc """
  Git version control business layer.

  Provides all git operations (status, diff, commit, push, PR, branches, merge, log)
  as composable functions. The Tool layer should delegate here.

  All functions take a context map with `:cwd` or `:workspace_path` for the working directory.
  """

  # -- Status --

  def status(ctx) do
    case run_git(["status", "--short", "-b"], ctx) do
      {:ok, output} ->
        lines = String.split(String.trim(output), "\n")
        {branch_line, file_lines} = parse_status_lines(lines)
        {:ok, %{"branch" => branch_line, "files" => file_lines, "raw" => output}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Diff --

  def diff(args, ctx) do
    staged? = args["staged"] || false
    opts = if staged?, do: ["diff", "--staged"], else: ["diff"]
    opts = if files = args["files"], do: opts ++ ["--"] ++ files, else: opts

    case run_git(opts, ctx) do
      {:ok, output} -> {:ok, %{"diff" => output}}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Commit --

  def commit(args, ctx) do
    message = args["message"]

    if is_nil(message) do
      {:error, "Missing required: message"}
    else
      files = args["files"]

      with :ok <- stage_files(files, ctx),
           {:ok, output} <- run_git(["commit", "-m", message], ctx) do
        {:ok, %{"message" => String.trim(output)}}
      end
    end
  end

  # -- Push --

  def push(args, ctx) do
    branch = args["branch"] || current_branch(ctx)
    remote = args["remote"] || "origin"

    case run_git(["push", remote, branch], ctx) do
      {:ok, output} -> {:ok, %{"result" => String.trim(output)}}
      {:error, reason} -> {:error, "Push failed: #{reason}"}
    end
  end

  # -- Create PR --

  def create_pr(args, ctx) do
    title = args["title"]
    body = args["body"] || ""
    base = args["base"] || "main"

    cond do
      is_nil(title) ->
        {:error, "Missing required: title"}

      not gh_available?() ->
        {:error, "GitHub CLI (gh) not found. Install it to create PRs."}

      true ->
        head = args["branch"] || current_branch(ctx)

        cmd_args = ["pr", "create", "--head", head, "--base", base, "--title", title]
        cmd_args = if body != "", do: cmd_args ++ ["--body", body], else: cmd_args

        case run_cmd("gh", cmd_args, ctx) do
          {:ok, output} ->
            url = extract_pr_url(output)
            {:ok, %{"url" => url, "raw" => String.trim(output)}}

          {:error, reason} ->
            {:error, "PR creation failed: #{reason}"}
        end
    end
  end

  # -- List Branches --

  def list_branches(ctx) do
    case run_git(["branch", "-a"], ctx) do
      {:ok, output} ->
        branches =
          output
          |> String.split("\n")
          |> Enum.map(&String.trim_leading(&1, "* "))
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        current = current_branch(ctx)
        {:ok, %{"branches" => branches, "current" => current}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Merge --

  def merge(args, ctx) do
    branch = args["branch"]

    if is_nil(branch) do
      {:error, "Missing required: branch"}
    else
      case run_git(["merge", branch], ctx) do
        {:ok, output} ->
          {:ok, %{"result" => String.trim(output)}}

        {:error, reason} ->
          if String.contains?(reason, "CONFLICT") do
            {:error, "Merge conflict. Resolve conflicts manually, then commit."}
          else
            {:error, "Merge failed: #{reason}"}
          end
      end
    end
  end

  # -- Log --

  def log(args, ctx) do
    max = args["max_count"] || 10
    format = "--format=%h|%an|%ar|%s"

    case run_git(["log", format, "-n", Integer.to_string(max)], ctx) do
      {:ok, output} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n")
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&parse_log_line/1)

        {:ok, %{"commits" => commits, "count" => length(commits)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Helpers --

  def current_branch(ctx) do
    case run_git(["rev-parse", "--abbrev-ref", "HEAD"], ctx) do
      {:ok, branch} -> String.trim(branch)
      _ -> "unknown"
    end
  end

  defp stage_files(nil, ctx) do
    case run_git(["add", "-A"], ctx) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Stage failed: #{reason}"}
    end
  end

  defp stage_files(files, ctx) when is_list(files) do
    case run_git(["add" | files], ctx) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Stage failed: #{reason}"}
    end
  end

  defp parse_status_lines(["## " <> _ = branch | rest]), do: {branch, rest}
  defp parse_status_lines(lines), do: {"(no branch info)", lines}

  defp parse_log_line(line) do
    case String.split(line, "|", parts: 4) do
      [hash, author, relative_date, message] ->
        %{"hash" => hash, "author" => author, "date" => relative_date, "message" => message}

      _ ->
        %{"raw" => line}
    end
  end

  defp run_git(args, ctx), do: run_cmd("git", args, ctx)

  defp run_cmd(cmd, args, ctx) do
    cwd = Map.get(ctx, :cwd) || Map.get(ctx, :workspace_path) || "."

    case System.cmd(cmd, args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, String.trim(output)}
    end
  rescue
    e in ErlangError -> {:error, "Command failed: #{Exception.message(e)}"}
  end

  defp gh_available? do
    case System.find_executable("gh") do
      nil -> false
      _ -> true
    end
  end

  defp extract_pr_url(output) do
    case Regex.run(~r{(https://github\.com/\S+/pull/\d+)}, output) do
      [url | _] -> url
      _ -> nil
    end
  end
end
