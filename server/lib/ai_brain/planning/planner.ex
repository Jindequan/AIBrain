defmodule AIBrain.Planning.Planner do
  @moduledoc """
  Entry point for the Planning system.

  Delegates to AIBrain.Planning.Agent for multi-turn interactive planning.
  """

  require Logger

  alias AIBrain.Planning.Agent

  @doc """
  Start a planning session for a user request.

  Returns `{:ok, plan}` where plan contains session_id and summary,
  or `{:error, reason}` on failure.
  """
  def plan(user_request, opts \\ []) do
    case Agent.run(user_request, opts) do
      {:ok, result} ->
        Logger.info("Planning completed: #{result.session_id}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Planning failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def replan(goal_id, feedback, opts \\ []) do
    prompt = """
    Replan goal #{goal_id}.

    Feedback:
    #{feedback}
    """

    plan(prompt, opts)
  end
end
