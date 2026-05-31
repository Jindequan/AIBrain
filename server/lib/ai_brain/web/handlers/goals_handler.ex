defmodule AIBrain.Web.Handlers.GoalsHandler do
  @moduledoc """
  HTTP handler for CRUD operations on Goals.

  All functions receive a Plug.Conn and return a Plug.Conn.
  """

  import Plug.Conn
  alias AIBrain.AgentRuntime.GoalDaemon
  alias AIBrain.Data.{EpisodicMemories, Goals, Runs}

  def handle_list(conn, params) do
    opts =
      []
      |> maybe_put_opt(:parent_id, params["parent_id"])
      |> maybe_put_opt(:status, params["status"])
      |> maybe_put_opt(:workspace_path, params["workspace_path"])

    {:ok, goals} = Goals.list(opts)
    json(conn, 200, %{goals: Enum.map(goals, &serialize_goal/1)})
  end

  def handle_get(conn, id) do
    case Goals.get(id) do
      {:ok, goal} -> json(conn, 200, serialize_goal(goal))
      {:error, :not_found} -> json(conn, 404, %{error: "Goal not found"})
    end
  end

  def handle_scan(conn, server \\ GoalDaemon) do
    case GoalDaemon.scan_now(server) do
      {:ok, run_ids} ->
        json(conn, 200, %{ok: true, started_run_ids: run_ids})

      {:error, reason} ->
        json(conn, 500, %{ok: false, error: inspect(reason)})
    end
  end

  def handle_create(conn, params) do
    case Goals.create(params) do
      {:ok, goal} -> json(conn, 201, serialize_goal(goal))
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_update(conn, id, params) do
    case Goals.update(id, params) do
      {:ok, updated} -> json(conn, 200, serialize_goal(updated))
      {:error, :not_found} -> json(conn, 404, %{error: "Goal not found"})
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_delete(conn, id) do
    case Goals.delete(id) do
      :ok -> json(conn, 200, %{message: "Deleted"})
      {:error, :not_found} -> json(conn, 404, %{error: "Goal not found"})
    end
  end

  def handle_get_events(conn, id, _params) do
    events = AIBrain.Data.Events.list_by_goal(id)
    json(conn, 200, %{events: events})
  end

  def handle_runs(conn, id, params) do
    limit = parse_int(params["limit"]) || 50

    case Goals.get(id) do
      {:ok, _goal} ->
        runs =
          Runs.list_runs_for_ref("goal", id, limit: limit)
          |> Enum.map(&serialize_run/1)

        json(conn, 200, %{goal_id: id, runs: runs})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Goal not found"})
    end
  end

  def handle_memories(conn, id, params) do
    limit = parse_int(params["limit"]) || 20

    case Goals.get(id) do
      {:ok, _goal} ->
        memories =
          id
          |> EpisodicMemories.get_by_goal(limit: clamp_limit(limit, 1, 100))
          |> Enum.map(&serialize_memory/1)

        json(conn, 200, %{goal_id: id, memories: memories})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Goal not found"})
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp serialize_goal(goal) do
    metadata = goal.metadata || %{}

    strategy = serialize_strategy(metadata["strategy"] || %{})

    %{
      id: goal.id,
      parent_id: goal.parent_id,
      title: goal.title,
      description: goal.description,
      status: goal.status,
      priority: goal.priority,
      workspace_path: goal.workspace_path,
      metadata: metadata,
      automation: %{
        autonomous: truthy?(metadata["autonomous"]) or int(metadata["autonomy_level"], 0) > 0,
        autonomy_level: int(metadata["autonomy_level"], 0),
        last_goal_daemon_run_id: metadata["last_goal_daemon_run_id"],
        last_review_started_at: metadata["last_review_started_at"],
        last_review_failed_at: metadata["last_review_failed_at"],
        last_review_error: metadata["last_review_error"],
        next_review_after: metadata["next_review_after"],
        last_strategy_run_id: metadata["last_strategy_run_id"],
        last_strategy_updated_at: metadata["last_strategy_updated_at"],
        last_report_artifact_id: metadata["last_report_artifact_id"],
        last_report_run_id: metadata["last_report_run_id"],
        last_report_path: metadata["last_report_path"],
        last_report_completed_at: metadata["last_report_completed_at"],
        last_owner_interaction_id: metadata["last_owner_interaction_id"],
        last_owner_interaction_requested_at: metadata["last_owner_interaction_requested_at"]
      },
      strategy: strategy,
      inserted_at: goal.inserted_at,
      updated_at: goal.updated_at
    }
  end

  defp serialize_strategy(strategy) when is_map(strategy) do
    assessment = strategy["assessment"] || strategy["current_assessment"] || ""

    strategy
    |> Map.put_new("assessment", assessment)
    |> Map.put_new("current_assessment", assessment)
  end

  defp serialize_strategy(_strategy), do: %{}

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp int(value, _default) when is_integer(value), do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp serialize_run(run) do
    %{
      id: run.id,
      source_type: run.source_type,
      source_id: run.source_id,
      status: run.status,
      phase: run.phase,
      mode: run.mode,
      title: run.title,
      objective: run.objective,
      output_summary: run.output_summary,
      error: run.error,
      inserted_at: run.inserted_at,
      updated_at: run.updated_at,
      completed_at: run.completed_at
    }
  end

  defp serialize_memory(memory) do
    %{
      id: memory.id,
      goal_id: memory.goal_id,
      task_id: memory.task_id,
      run_id: memory.run_id,
      narrative: memory.narrative,
      objective: memory.objective,
      approach: memory.approach,
      key_decisions: memory.key_decisions || %{},
      success_score: memory.success_score,
      importance_score: memory.importance_score,
      lessons: memory.lessons || [],
      difficulties: memory.difficulties || %{},
      tool_usage_summary: memory.tool_usage_summary || %{},
      tags: memory.tags || [],
      period_start: memory.period_start,
      period_end: memory.period_end,
      inserted_at: memory.inserted_at,
      updated_at: memory.updated_at
    }
  end

  defp clamp_limit(value, min, max) when is_integer(value) do
    value
    |> Kernel.max(min)
    |> Kernel.min(max)
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
