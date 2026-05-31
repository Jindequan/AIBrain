defmodule AIBrain.Tool.Builtin.Git do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Git tool — thin adapter that delegates to Business.Git.
  """

  alias AIBrain.Business.Git

  def name, do: "git"

  def description,
    do:
      "Git version control: status, diff, commit, push, create PR, list branches, merge. Operates in the current workspace."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => [
            "status",
            "diff",
            "commit",
            "push",
            "create_pr",
            "list_branches",
            "merge",
            "log"
          ],
          "description" => "Git action to perform"
        },
        "message" => %{"type" => "string", "description" => "Commit message (for commit action)"},
        "branch" => %{
          "type" => "string",
          "description" => "Branch name (for merge, push, create_pr)"
        },
        "base" => %{"type" => "string", "description" => "Base branch for PR (default: main)"},
        "title" => %{"type" => "string", "description" => "PR title (for create_pr)"},
        "body" => %{"type" => "string", "description" => "PR description (for create_pr)"},
        "files" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Specific files to stage (for commit, default: all)"
        },
        "max_count" => %{"type" => "integer", "description" => "Max commits for log (default 10)"}
      },
      "required" => ["action"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :workspace_write

  # -- Dispatch — thin delegation to Business.Git --

  def execute(%{"action" => "status"}, ctx), do: Git.status(ctx)
  def execute(%{"action" => "diff"} = args, ctx), do: Git.diff(args, ctx)
  def execute(%{"action" => "commit"} = args, ctx), do: Git.commit(args, ctx)
  def execute(%{"action" => "push"} = args, ctx), do: Git.push(args, ctx)
  def execute(%{"action" => "create_pr"} = args, ctx), do: Git.create_pr(args, ctx)
  def execute(%{"action" => "list_branches"}, ctx), do: Git.list_branches(ctx)
  def execute(%{"action" => "merge"} = args, ctx), do: Git.merge(args, ctx)
  def execute(%{"action" => "log"} = args, ctx), do: Git.log(args, ctx)

  def execute(%{}, _),
    do:
      {:error, "Action must be: status, diff, commit, push, create_pr, list_branches, merge, log"}
end
