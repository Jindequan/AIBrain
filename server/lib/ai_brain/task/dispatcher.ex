defmodule AIBrain.Task.Dispatcher do
  @moduledoc """
  Polls for pending dispatchable tasks and drives them through AgentRuntime.Orchestrator.

  A task is dispatchable when:
    - status = "pending"
    - all depends_on tasks are completed

  On run completion, updates task status and publishes to Channel.Bus.
  """

  use GenServer
  require Logger

  alias AIBrain.Data.{Tasks, Goals}
  alias AIBrain.Channel.Bus
  alias AIBrain.AgentRuntime.Orchestrator

  @default_poll_interval 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Cast a hint that a new pending task exists — triggers immediate scan."
  def notify_pending(server \\ __MODULE__, task_id) do
    GenServer.cast(server, {:notify_pending, task_id})
  end

  @doc "Synchronously dispatch all pending tasks now (used in tests)."
  def dispatch_now(server \\ __MODULE__) do
    GenServer.call(server, :dispatch_now)
  end

  @doc false
  def start_task_run(input, opts, runner \\ &Orchestrator.start_async/2) do
    task_id = get_in(opts, [:context, :task_id]) || get_in(opts, [:metadata, :task_id])
    goal_id = get_in(opts, [:context, :goal_id]) || get_in(opts, [:metadata, :goal_id])

    workspace_path =
      get_in(opts, [:context, :workspace_path]) || get_in(opts, [:metadata, :workspace_path])

    autonomy_level =
      get_in(opts, [:context, :autonomy_level]) || get_in(opts, [:metadata, :autonomy_level])

    schedule_id =
      get_in(opts, [:context, :schedule_id]) || get_in(opts, [:metadata, :schedule_id])

    assistant_name = Keyword.get(opts, :assistant_name, "default")
    runtime_opts = task_runtime_opts(opts)

    runner.(
      %{
        source_type: "task",
        source_id: task_id,
        objective: input,
        title: task_id && "Task #{task_id}",
        mode: "background",
        task_id: task_id,
        goal_id: goal_id,
        schedule_id: schedule_id,
        workspace_path: workspace_path,
        autonomy_level: autonomy_level,
        messages: [%{role: "user", content: input}],
        metadata: %{
          "assistant_name" => assistant_name,
          "entrypoint" => "task.dispatcher",
          "required_skills" => Keyword.get(opts, :required_skills, []),
          "schedule_id" => schedule_id,
          "workspace_path" => workspace_path,
          "autonomy_level" => autonomy_level
        },
        opts: runtime_opts
      },
      runtime_opts
    )
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    runner = Keyword.get(opts, :runner, &default_runner/3)
    enabled = Keyword.get(opts, :enabled, true)

    if enabled do
      schedule_poll(interval)
    end

    {:ok, %{poll_interval: interval, runner: runner, enabled: enabled}}
  end

  @impl true
  def handle_cast({:notify_pending, _task_id}, %{enabled: false} = state), do: {:noreply, state}

  def handle_cast({:notify_pending, _task_id}, state) do
    do_dispatch(state.runner)
    {:noreply, state}
  end

  @impl true
  def handle_call(:dispatch_now, _from, %{enabled: false} = state), do: {:reply, :disabled, state}

  def handle_call(:dispatch_now, _from, state) do
    do_dispatch(state.runner)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:poll, %{enabled: false} = state), do: {:noreply, state}

  def handle_info(:poll, state) do
    do_dispatch(state.runner)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:run_complete, run_id, result}, state) do
    handle_run_complete(run_id, result, state.runner)
    {:noreply, state}
  end

  defp do_dispatch(runner) do
    try do
      Tasks.list_pending_dispatchable()
      |> Enum.each(&dispatch_task(&1, runner))
    rescue
      e ->
        Logger.debug("Dispatcher: skipping dispatch cycle (#{Exception.message(e)})")
    catch
      :exit, reason ->
        Logger.debug("Dispatcher: skipping dispatch cycle (exit: #{inspect(reason)})")
    end
  end

  defp dispatch_task(task, runner) do
    # Re-fetch to guard against concurrent dispatch
    case Tasks.get_task(task.id) do
      {:ok, %{status: "pending"} = fresh_task} ->
        input = build_task_prompt(fresh_task)
        task_metadata = fresh_task.metadata || %{}
        schedule_id = task_metadata["schedule_id"] || task_metadata[:schedule_id]
        workspace_path = task_metadata["workspace_path"] || task_metadata[:workspace_path]
        autonomy_level = task_metadata["autonomy_level"] || task_metadata[:autonomy_level]
        max_turns = task_metadata["max_turns"] || task_metadata[:max_turns]
        max_wall_time = task_metadata["max_wall_time"] || task_metadata[:max_wall_time]

        opts = [
          notify: self(),
          metadata: %{
            task_id: fresh_task.id,
            goal_id: fresh_task.goal_id,
            schedule_id: schedule_id,
            workspace_path: workspace_path,
            autonomy_level: autonomy_level,
            max_turns: max_turns,
            max_wall_time: max_wall_time
          },
          context: %{
            source: "task",
            task_id: fresh_task.id,
            goal_id: fresh_task.goal_id,
            schedule_id: schedule_id,
            workspace_path: workspace_path,
            autonomy_level: autonomy_level
          },
          required_skills: fresh_task.required_skills || []
        ]

        case runner.("default", input, opts) do
          {:ok, run_id} ->
            Tasks.update_run(fresh_task.id, run_id)
            Logger.info("Dispatcher: task #{fresh_task.id} → run #{run_id}")

          {:error, reason} ->
            Tasks.update_task_result(fresh_task, "failed", "Dispatch failed: #{inspect(reason)}")

            Logger.error(
              "Dispatcher: failed to dispatch task #{fresh_task.id}: #{inspect(reason)}"
            )
        end

      {:ok, task} ->
        Logger.debug("Dispatcher: skipping task #{task.id} (status=#{task.status})")

      {:error, :not_found} ->
        Logger.debug("Dispatcher: task not found during dispatch")
    end
  end

  defp handle_run_complete(run_id, result, runner) do
    case Tasks.get_by_run_id(run_id) do
      {:ok, task} when task.status == "running" ->
        case result do
          {:ok, text, _msgs} ->
            Tasks.update_task_result(task, "completed", text)

            Bus.publish(%{
              type: :task_completed,
              task_id: task.id,
              task_title: task.title,
              goal_id: task.goal_id,
              result_summary: AIBrain.AgentRuntime.RunLifecycle.summarize(text)
            })

            Logger.info("Dispatcher: task #{task.id} completed")

            # Check if the parent goal is now fully complete
            check_goal_completion(task.goal_id)

            # Trigger immediate dispatch — downstream tasks may now be unblocked
            do_dispatch(runner)

          {:error, reason} ->
            Tasks.update_task_result(task, "failed", inspect(reason))

            Bus.publish(%{
              type: :task_failed,
              task_id: task.id,
              task_title: task.title,
              goal_id: task.goal_id,
              reason: inspect(reason)
            })

            Logger.info("Dispatcher: task #{task.id} failed: #{inspect(reason)}")

            # Check if goal should be marked failed
            check_goal_failure(task.goal_id)

          {:suspended, _meta} ->
            Bus.publish(%{
              type: :approval_needed,
              task_id: task.id,
              goal_id: task.goal_id
            })

            Logger.info("Dispatcher: task #{task.id} suspended for approval")
        end

      {:ok, task} ->
        Logger.debug(
          "Dispatcher: run #{run_id} already resolved (task #{task.id} status=#{task.status})"
        )

      {:error, :not_found} ->
        Logger.debug("Dispatcher: run #{run_id} not linked to a task")
    end
  end

  # Check if all tasks under a goal are completed → mark goal completed
  defp check_goal_completion(nil), do: :ok

  defp check_goal_completion(goal_id) do
    case Goals.get(goal_id) do
      {:ok, _goal} ->
        tasks = Tasks.list_tasks(goal_id)

        all_done = Enum.all?(tasks, fn t -> t.status in ["completed"] end)

        if all_done and length(tasks) > 0 do
          {:ok, _} = Goals.update(goal_id, %{status: "completed"})

          Bus.publish(%{
            type: :goal_completed,
            goal_id: goal_id
          })

          Logger.info("Dispatcher: goal #{goal_id} fully completed")
        end

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("Dispatcher: check_goal_completion failed: #{Exception.message(e)}")
  end

  # Check if goal should be marked as failed (any task failed, no pending/running left)
  defp check_goal_failure(nil), do: :ok

  defp check_goal_failure(goal_id) do
    case Goals.get(goal_id) do
      {:ok, %{status: status}} when status != "completed" ->
        tasks = Tasks.list_tasks(goal_id)

        has_failed = Enum.any?(tasks, fn t -> t.status == "failed" end)
        all_resolved = Enum.all?(tasks, fn t -> t.status in ["completed", "failed"] end)

        if has_failed and all_resolved do
          {:ok, _} = Goals.update(goal_id, %{status: "paused"})

          Bus.publish(%{
            type: :goal_failed,
            goal_id: goal_id
          })

          Logger.info("Dispatcher: goal #{goal_id} marked as failed")
        end

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("Dispatcher: check_goal_failure failed: #{Exception.message(e)}")
  end

  defp build_task_prompt(task) do
    goal_context =
      case Goals.get(task.goal_id) do
        {:ok, goal} -> "目标背景：#{goal.title} — #{goal.description || ""}\n\n"
        _ -> ""
      end

    """
    #{goal_context}任务：#{task.title}
    任务说明：#{task.description || "（无额外说明）"}
    任务ID：#{task.id}

    执行完成后，调用 update_task_status 工具标记结果和产出。
    """
  end

  defp default_runner(assistant_name, input, opts) do
    opts = Keyword.put(opts, :assistant_name, assistant_name)
    start_task_run(input, opts)
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp task_runtime_opts(opts) do
    metadata = Keyword.get(opts, :metadata, %{})

    opts
    |> Keyword.put_new(:permission_mode, :approval_required)
    |> Keyword.put_new(:autonomy_allowed_tools, ["goal_task"])
    |> maybe_put_runtime(:workspace_path, metadata[:workspace_path])
    |> maybe_put_runtime(:autonomy_level, metadata[:autonomy_level])
    |> maybe_put_runtime(:max_turns, metadata[:max_turns])
    |> maybe_put_runtime(:max_wall_time, metadata[:max_wall_time])
  end

  defp maybe_put_runtime(opts, _key, nil), do: opts
  defp maybe_put_runtime(opts, _key, ""), do: opts
  defp maybe_put_runtime(opts, key, value), do: Keyword.put_new(opts, key, value)
end
