defmodule AIBrain.AgentRuntime.GoalDaemon do
  @moduledoc """
  Periodically reviews autonomous long-term goals and starts goal_tick runs.

  This module is intentionally a coordinator, not another execution engine.
  It reads `goals`, `tasks`, and `runs`, then delegates work to Orchestrator so
  every autonomous background action remains visible in the unified run log.
  """

  use GenServer
  require Logger

  alias AIBrain.AgentRuntime.{GoalMetadata, Orchestrator}
  alias AIBrain.Data.{Goals, Runs, Tasks}

  @default_scan_interval 900
  @default_cooldown_seconds 3600

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def scan_now(server \\ __MODULE__) do
    GenServer.call(server, :scan, 60_000)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :scan_interval, @default_scan_interval) * 1000
    runner = Keyword.get(opts, :runner, &default_runner/2)
    schedule_scan(interval)
    Logger.info("GoalDaemon: started (scan every #{div(interval, 1000)}s)")
    {:ok, %{scan_interval: interval, runner: runner}}
  end

  @impl true
  def handle_call(:scan, _from, state) do
    result = scan_goals(state.runner)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:scan, state) do
    planned_at = System.monotonic_time(:millisecond)
    scan_goals(state.runner)
    elapsed = System.monotonic_time(:millisecond) - planned_at
    next_delay = max(state.scan_interval - elapsed, 0)
    schedule_scan(next_delay)
    {:noreply, state}
  end

  defp scan_goals(runner) do
    with {:ok, goals} <- Goals.list(status: "active") do
      started =
        goals
        |> Enum.filter(&autonomous?/1)
        |> Enum.filter(&due_for_review?/1)
        |> Enum.reduce([], fn goal, acc ->
          case start_goal_tick(goal, runner) do
            {:ok, run_id} ->
              [run_id | acc]

            {:error, reason} ->
              Logger.warning(
                "GoalDaemon: failed to start review for #{goal.id}: #{inspect(reason)}"
              )

              acc
          end
        end)

      {:ok, Enum.reverse(started)}
    end
  rescue
    e ->
      Logger.warning("GoalDaemon: scan failed: #{Exception.message(e)}")
      {:error, e}
  end

  defp start_goal_tick(goal, runner) do
    tasks = Tasks.list_tasks(goal.id)
    autonomy_level = autonomy_level(goal)
    cooldown = metadata_int(goal, "goal_daemon_cooldown_seconds", @default_cooldown_seconds)
    next_review_after = DateTime.utc_now() |> DateTime.add(cooldown, :second)

    attrs = %{
      source_type: "goal",
      source_id: goal.id,
      goal_id: goal.id,
      title: "Goal review: #{goal.title}",
      objective: objective(goal, tasks),
      mode: "goal_tick",
      autonomy_level: autonomy_level,
      workspace_path: goal.workspace_path,
      messages: [%{role: "user", content: objective(goal, tasks)}],
      metadata: %{
        "entrypoint" => "goal.daemon",
        "goal_id" => goal.id,
        "goal_title" => goal.title,
        "autonomy_level" => autonomy_level
      },
      opts: [
        permission_mode: :approval_required,
        autonomy_allowed_tools: ["goal_task"],
        max_turns: metadata_int(goal, "max_turns", 80),
        max_wall_time: metadata_int(goal, "max_wall_time", 900)
      ]
    }

    case runner.(attrs, attrs.opts) do
      {:ok, run_id} = ok ->
        mark_review_started(goal, run_id, next_review_after)
        ok

      {:error, reason} = error ->
        mark_review_failed(goal, reason, next_review_after)
        error
    end
  end

  defp objective(goal, tasks) do
    summary = task_summary(tasks)
    strategy = strategy_summary(goal)
    memory = memory_summary(goal)

    """
    你正在后台推进一个长期目标。请认真审查当前目标、已有任务和最近进展，判断下一步应该做什么。

    目标：#{goal.title}
    描述：#{goal.description || "无"}
    当前任务概况：#{summary}
    当前策略状态：#{strategy}
    相关历史记忆：#{memory}

    要求：
    1. 盘点目标是否仍然有效、是否需要澄清或暂停。
    2. 识别阻塞、风险、遗漏和下一步行动。
    3. 如需要继续推进，创建少量明确、可执行、可验证的后续任务。
    4. 如需要主人授权、外部账号、敏感操作或不可逆操作，必须暂停并请求确认。
    5. 必须调用 goal_task.record_goal_strategy，记录 current_assessment、next_actions、blockers、needs_owner_input、next_focus。
    6. 输出一份简短阶段性报告，说明本轮判断、创建/更新了什么、下一次应关注什么。
    """
  end

  defp strategy_summary(goal) do
    current = GoalMetadata.current_strategy(goal)
    actions = GoalMetadata.next_actions(goal)
    blockers = GoalMetadata.blockers(goal)
    needs_owner = GoalMetadata.needs_owner_input?(goal)
    next_review = GoalMetadata.next_review_at(goal)

    if current == "" and actions == [] and blockers == [] do
      "暂无结构化策略"
    else
      Jason.encode!(%{
        current_assessment: current,
        next_actions: actions,
        blockers: blockers,
        needs_owner_input: needs_owner,
        next_review_at: next_review
      })
    end
  end

  defp task_summary([]), do: "暂无任务"

  defp task_summary(tasks) do
    counts = Enum.frequencies_by(tasks, & &1.status)

    tasks_text =
      tasks
      |> Enum.take(12)
      |> Enum.map(fn task -> "- #{task.status}: #{task.title}" end)
      |> Enum.join("\n")

    "总数 #{length(tasks)}，状态 #{inspect(counts)}\n#{tasks_text}"
  end

  defp memory_summary(goal) do
    case AIBrain.Memory.recall(goal.id, type: :episodic, limit: 5) do
      {:ok, []} ->
        "暂无历史记忆"

      {:ok, entries} ->
        entries
        |> Enum.map(fn entry ->
          content = entry[:content] || ""
          lessons = entry[:lessons] || []
          lesson_text = if lessons == [], do: "", else: "；经验：" <> Enum.join(lessons, "；")
          "- #{content}#{lesson_text}"
        end)
        |> Enum.join("\n")

      _ ->
        "暂无历史记忆"
    end
  rescue
    _ -> "暂无历史记忆"
  end

  defp autonomous?(goal) do
    metadata_truthy?(goal, "autonomous") or autonomy_level(goal) > 0
  end

  defp autonomy_level(goal) do
    metadata_int(goal, "autonomy_level", 0)
  end

  defp metadata_truthy?(goal, key) do
    metadata = goal.metadata || %{}

    case Map.get(metadata, key) || Map.get(metadata, String.to_existing_atom(key)) do
      true -> true
      "true" -> true
      1 -> true
      "1" -> true
      _ -> false
    end
  rescue
    ArgumentError -> false
  end

  defp metadata_int(goal, key, default) do
    metadata = goal.metadata || %{}
    value = Map.get(metadata, key) || Map.get(metadata, existing_atom(key))

    cond do
      is_integer(value) ->
        value

      is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end

      true ->
        default
    end
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp due_for_review?(goal) do
    not active_goal_run?(goal.id) and next_review_due?(goal) and cooldown_elapsed?(goal)
  end

  defp active_goal_run?(goal_id) do
    Runs.list_runs_for_ref("goal", goal_id,
      status: ["pending", "running", "waiting_approval", "waiting_assistant"],
      limit: 1
    ) != []
  end

  defp cooldown_elapsed?(goal) do
    cooldown = metadata_int(goal, "goal_daemon_cooldown_seconds", @default_cooldown_seconds)

    case Runs.list_runs_for_ref("goal", goal.id, mode: "goal_tick", limit: 1) do
      [] ->
        true

      [run | _] ->
        # If the last review run failed (e.g. provider unavailable), skip the
        # cooldown so we retry on the next scan instead of waiting the full period.
        run.status == "failed" or seconds_since(run.inserted_at) >= cooldown
    end
  end

  defp next_review_due?(goal) do
    case GoalMetadata.next_review_at(goal) do
      nil ->
        true

      value ->
        case DateTime.from_iso8601(to_string(value)) do
          {:ok, dt, _offset} -> DateTime.compare(dt, DateTime.utc_now()) != :gt
          _ -> true
        end
    end
  end

  defp mark_review_started(goal, run_id, next_review_after) do
    next_review = next_review_after |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    metadata =
      goal.metadata
      |> normalize_metadata()
      |> Map.merge(%{
        "last_goal_daemon_run_id" => run_id,
        "next_review_after" => next_review,
        "next_review_at" => next_review
      })

    # Only clear last_review_error when the run actually proves successful.
    # The run was just created and hasn't executed yet — don't claim success.
    Goals.update(goal.id, %{metadata: metadata})
    :ok
  rescue
    e ->
      Logger.warning("GoalDaemon: failed to mark review for #{goal.id}: #{Exception.message(e)}")
      :ok
  end

  defp mark_review_failed(goal, reason, next_review_after) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    next_review = next_review_after |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    metadata =
      goal.metadata
      |> normalize_metadata()
      |> Map.merge(%{
        "last_review_failed_at" => now,
        "last_review_error" => inspect(reason),
        "next_review_after" => next_review,
        "next_review_at" => next_review
      })

    Goals.update(goal.id, %{metadata: metadata})
    :ok
  rescue
    e ->
      Logger.warning(
        "GoalDaemon: failed to mark review failure for #{goal.id}: #{Exception.message(e)}"
      )

      :ok
  end

  defp normalize_metadata(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), val} end)
  end

  defp normalize_metadata(_), do: %{}

  defp seconds_since(%NaiveDateTime{} = dt) do
    DateTime.diff(DateTime.utc_now(), DateTime.from_naive!(dt, "Etc/UTC"), :second)
  end

  defp seconds_since(%DateTime{} = dt) do
    DateTime.diff(DateTime.utc_now(), dt, :second)
  end

  defp seconds_since(_), do: @default_cooldown_seconds

  defp default_runner(attrs, opts) do
    Orchestrator.start_async(attrs, opts)
  end

  defp schedule_scan(interval) do
    Process.send_after(self(), :scan, interval)
  end
end
