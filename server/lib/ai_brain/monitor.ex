defmodule AIBrain.Monitor do
  @moduledoc """
  Background monitor system for proactive agent behavior.

  Runs periodic checks based on cron expressions, executing LLM-driven
  actions and recording results. Enables the agent to proactively monitor
  conditions (e.g. "check email every 30 minutes for urgent messages").
  """

  use GenServer
  require Logger

  alias AIBrain.AgentRuntime.FileStore
  alias AIBrain.Data.{Schedule, Schedules}
  alias AIBrain.Repo
  alias AIBrain.Scheduling.Cron

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: Keyword.get(opts, :name, __MODULE__))
  end

  # ── Public API ───────────────────────────────────────────────

  @doc "List all active monitors."
  def list do
    Schedules.list_schedules()
    |> Enum.filter(&monitor_schedule?/1)
    |> Enum.map(fn schedule ->
      action = schedule.action_config || %{}

      %{
        id: schedule.id,
        name: schedule.name,
        type: action["kind"] || "monitor",
        cron: get_in(schedule.trigger_config || %{}, ["cron"]),
        action: action["prompt"] || action["message"] || action["description"] || "",
        status: schedule.status,
        next_fire: format_dt(schedule.next_fire_at),
        last_result: schedule.last_result,
        created_at: format_dt(schedule.inserted_at)
      }
    end)
  rescue
    e ->
      Logger.error("AIBrain.Monitor.list failed: #{Exception.message(e)}")
      []
  end

  @doc "Create a new monitor."
  def create(name, action, cron_expression) do
    next = next_cron_fire(cron_expression)

    case Schedules.create_schedule(%{
           "id" => "mon-#{System.unique_integer([:positive])}",
           "name" => name,
           "trigger_type" => "cron",
           "trigger_config" => %{"cron" => cron_expression},
           "action_type" => "run_query",
           "action_config" => %{"kind" => "monitor", "prompt" => action},
           "status" => "active",
           "next_fire_at" => next
         }) do
      {:ok, schedule} -> {:ok, schedule.id}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, "Failed to create monitor: #{Exception.message(e)}"}
  end

  @doc "Delete a monitor."
  def delete(id) do
    case Schedules.get_schedule(id) do
      {:ok, schedule} ->
        if monitor_schedule?(schedule),
          do: Schedules.delete_schedule(id),
          else: {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  rescue
    e ->
      Logger.error("AIBrain.Monitor.delete failed: #{Exception.message(e)}")
      {:error, :not_found}
  end

  @doc "Get monitor logs."
  def logs(monitor_id, limit \\ 10) do
    result =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT id, status, result, result_path, summary, triggered_at, completed_at FROM monitor_logs WHERE monitor_id = ? ORDER BY triggered_at DESC LIMIT ?",
        [monitor_id, limit]
      )

    Enum.map(result.rows, fn [
                               id,
                               status,
                               result,
                               result_path,
                               summary,
                               triggered_at,
                               completed_at
                             ] ->
      %{
        id: id,
        status: status,
        result: result || read_result_path(result_path),
        result_path: result_path,
        summary: summary || "",
        triggered_at: triggered_at,
        completed_at: completed_at
      }
    end)
  rescue
    e ->
      Logger.error("AIBrain.Monitor.logs failed: #{Exception.message(e)}")
      []
  end

  # ── Subscriber API ───────────────────────────────────────────

  # ── GenServer ────────────────────────────────────────────────

  @impl true
  def init(_) do
    schedule_tick()
    Logger.info("Monitor: started")
    {:ok, %{subscribers: MapSet.new()}}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_call({:notify, event}, _from, %{subscribers: subscribers} = state) do
    notify_subscribers(event, subscribers)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_info(:tick, state) do
    check_due_monitors()
    schedule_tick()
    {:noreply, state}
  end

  defp notify_subscribers(event, subscribers) do
    message = {:monitor_notification, event}

    Enum.each(subscribers, fn pid ->
      if Process.alive?(pid), do: send(pid, message)
    end)
  end

  defp schedule_tick do
    # Check every 30 seconds
    Process.send_after(self(), :tick, 30_000)
  end

  defp check_due_monitors do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Schedules.list_due_schedules()
    |> Enum.filter(&monitor_schedule?/1)
    |> Enum.each(fn schedule ->
      claim_monitor(schedule.id, now)

      Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
        action = schedule.action_config || %{}
        prompt = action["prompt"] || action["message"] || action["description"] || ""
        execute_monitor(schedule.id, schedule.name, prompt)
      end)
    end)
  rescue
    e ->
      Logger.error("AIBrain.Monitor.check_due_monitors failed: #{Exception.message(e)}")
      :ok
  end

  defp claim_monitor(id, now) do
    import Ecto.Query

    far_future =
      DateTime.utc_now()
      |> DateTime.add(86_400, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(s in Schedule,
        where:
          s.id == ^id and s.status == "active" and
            (is_nil(s.next_fire_at) or s.next_fire_at <= ^now)
      ),
      set: [next_fire_at: far_future]
    )
  end

  @doc "Subscribe the calling process to monitor execution notifications."
  def subscribe do
    GenServer.call(__MODULE__, {:subscribe, self()}, 10_000)
  end

  @doc "Unsubscribe from monitor execution notifications."
  def unsubscribe do
    GenServer.call(__MODULE__, {:unsubscribe, self()}, 10_000)
  end

  defp execute_monitor(id, name, action) do
    log_id = create_log(id)
    Logger.info("Monitor: executing #{name} (#{id})")

    start_time = DateTime.utc_now()

    {result_text, result_path} =
      case run_llm_check(id, name, action) do
        {:ok, text, run_id} -> {text, FileStore.output_path(run_id)}
        {:error, reason} -> {"Monitor failed: #{inspect(reason)}", nil}
      end

    completed_at = DateTime.utc_now()
    summary = String.slice(result_text, 0, 500)
    complete_log(log_id, result_text, result_path, summary)

    # Update next_fire_at
    cron = fetch_cron(id)
    next = if cron, do: next_cron_fire(cron), else: nil

    Schedules.update_schedule(id, %{"last_result" => summary, "next_fire_at" => next})

    # Notify subscribers
    GenServer.call(
      __MODULE__,
      {:notify,
       %{
         monitor_id: id,
         name: name,
         result: summary,
         started_at: start_time,
         completed_at: completed_at
       }},
      10_000
    )
  rescue
    e ->
      Logger.error("Monitor #{id} crashed: #{Exception.message(e)}")
  end

  defp run_llm_check(schedule_id, name, action) do
    messages = [
      %{
        role: "system",
        content:
          "You are a proactive monitor. Execute the following check and report what you observe. Be concise."
      },
      %{role: "user", content: action}
    ]

    opts = [
      tools: builtin_tools(),
      max_turns: 3,
      max_wall_time: 300,
      timeout: 60_000,
      on_event: fn _ -> :ok end
    ]

    case AIBrain.AgentRuntime.Orchestrator.start(
           %{
             source_type: "schedule",
             source_id: schedule_id,
             schedule_id: schedule_id,
             mode: "scheduled",
             title: "Monitor: #{name}",
             objective: action,
             messages: messages,
             metadata: %{
               "kind" => "monitor",
               "entrypoint" => "monitor"
             },
             opts: opts
           },
           opts
         ) do
      {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
        {:ok, text, run_id}

      {:ok, %{result: {:error, reason}}} ->
        {:error, reason}

      {:ok, %{result: other}} ->
        {:error, {:unexpected_result, other}}

      error ->
        error
    end
  end

  defp read_result_path(nil), do: nil

  defp read_result_path(path) when is_binary(path) do
    case File.read(path) do
      {:ok, text} -> text
      {:error, _} -> nil
    end
  end

  defp read_result_path(_), do: nil

  defp builtin_tools do
    AIBrain.Tool.Registry.to_api_format(AIBrain.Tool.Registry)
  end

  defp create_log(monitor_id) do
    id = "mlog-#{System.unique_integer([:positive])}"
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "INSERT INTO monitor_logs (id, monitor_id, status, triggered_at) VALUES (?, ?, 'running', ?)",
      [id, monitor_id, now]
    )

    id
  rescue
    e ->
      Logger.error("AIBrain.Monitor.create_log failed: #{Exception.message(e)}")
      nil
  end

  defp complete_log(nil, _result, _result_path, _summary), do: :ok

  defp complete_log(log_id, result, result_path, summary) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    legacy_result = if result_path, do: nil, else: result

    Ecto.Adapters.SQL.query!(
      AIBrain.Repo,
      "UPDATE monitor_logs SET status = 'completed', result = ?, result_path = ?, summary = ?, completed_at = ? WHERE id = ?",
      [legacy_result, result_path, summary, now, log_id]
    )
  rescue
    e ->
      Logger.error("AIBrain.Monitor.complete_log failed: #{Exception.message(e)}")
      :ok
  end

  defp fetch_cron(monitor_id) do
    case Schedules.get_schedule(monitor_id) do
      {:ok, schedule} -> get_in(schedule.trigger_config || %{}, ["cron"])
      _ -> nil
    end
  rescue
    e ->
      Logger.error("AIBrain.Monitor.fetch_cron failed: #{Exception.message(e)}")
      nil
  end

  defp next_cron_fire(cron_expr) when is_binary(cron_expr) do
    case Cron.parse(cron_expr) do
      {:ok, parsed} ->
        case Cron.next_fire(parsed, DateTime.utc_now()) do
          {:ok, next} ->
            DateTime.truncate(next, :second)

          {:error, _reason} ->
            fallback_next_fire()
        end

      {:error, _reason} ->
        fallback_next_fire()
    end
  rescue
    _ -> fallback_next_fire()
  end

  defp fallback_next_fire do
    DateTime.utc_now()
    |> DateTime.add(300, :second)
    |> DateTime.truncate(:second)
  end

  defp monitor_schedule?(%Schedule{} = schedule) do
    kind = get_in(schedule.action_config || %{}, ["kind"])
    kind in ["monitor", "scheduled_query"]
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp format_dt(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
end
