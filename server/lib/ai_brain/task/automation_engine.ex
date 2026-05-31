defmodule AIBrain.Task.AutomationEngine do
  @moduledoc """
  GenServer that periodically scans the schedules table and fires
  rules whose trigger conditions are met (cron, time, etc).

  Each fire creates a Task record to track execution.
  """

  use GenServer
  require Logger
  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Data.{Schedule, Tasks}
  alias AIBrain.Scheduling.Cron
  alias AIBrain.Channel.Bus

  @default_scan_interval 60

  # ── Public API ──────────────────────────────────────────

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Trigger an immediate scan of all automation rules"
  def scan_now(server \\ __MODULE__) do
    GenServer.call(server, :scan, 60_000)
  end

  @doc """
  Inject an external event to trigger matching automation rules.
  Used by FileWatcher and other event sources.
  """
  def inject_event(event_type, event_data, server \\ __MODULE__) do
    GenServer.cast(server, {:inject_event, event_type, event_data})
  end

  # ── Callbacks ───────────────────────────────────────────

  def init(opts) do
    interval = Keyword.get(opts, :scan_interval, @default_scan_interval) * 1000
    runner = Keyword.get(opts, :runner, &default_runner/2)
    schedule_next_scan(interval)
    Logger.info("Automation.Engine: started (scan every #{div(interval, 1000)}s)")
    {:ok, %{scan_interval: interval, runner: runner}}
  end

  def handle_call(:scan, _from, state) do
    fired = scan_all_rules(state.runner)
    {:reply, {:ok, fired}, state}
  end

  def handle_info(:scan, state) do
    # Track when this scan was due so we can compensate for processing delay.
    # Without this, a 5s scan every 60s becomes an effective 65s interval,
    # which can drift past minute boundaries and skip cron firings.
    planned_at = System.monotonic_time(:millisecond)
    scan_all_rules(state.runner)
    elapsed = System.monotonic_time(:millisecond) - planned_at
    next_delay = max(state.scan_interval - elapsed, 0)
    schedule_next_scan(next_delay)
    {:noreply, state}
  end

  def handle_cast({:inject_event, event_type, event_data}, state) do
    fire_event_rules(event_type, event_data, state.runner)
    {:noreply, state}
  end

  # ── Scan Logic ──────────────────────────────────────────

  defp schedule_next_scan(ms) do
    Process.send_after(self(), :scan, ms)
  end

  defp scan_all_rules(runner) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rules =
      Repo.all(
        from(s in Schedule,
          where: s.status == "active"
        )
      )

    Enum.reduce(rules, [], fn rule, acc ->
      case should_fire?(rule, now) do
        {:fire, context} ->
          case fire_rule(rule, now, context, runner) do
            {:ok, _rule} ->
              [rule.id | acc]

            {:error, reason} ->
              Logger.error("Automation.Engine: rule #{rule.id} fire failed: #{inspect(reason)}")
              acc
          end

        :skip ->
          acc
      end
    end)
  end

  defp should_fire?(rule, now) do
    case rule.trigger_type do
      "cron" ->
        cron_expr = get_in(rule.trigger_config, ["cron"])

        case cron_expr do
          nil ->
            :skip

          expr ->
            case Cron.parse(expr) do
              {:ok, cron} ->
                if Cron.matches?(cron, now) do
                  if fire_already_this_minute?(rule, now) do
                    :skip
                  else
                    next = calculate_next(cron, now)
                    {:fire, %{next_fire_at: next, trigger_info: %{"cron" => expr}}}
                  end
                else
                  :skip
                end

              {:error, _} ->
                Logger.warning("Automation.Engine: invalid cron '#{expr}' for rule #{rule.id}")
                :skip
            end
        end

      "time" ->
        next_fire = rule.next_fire_at

        cond do
          is_nil(next_fire) -> :skip
          DateTime.compare(next_fire, now) != :gt -> {:fire, %{next_fire_at: nil}}
          true -> :skip
        end

      "event" ->
        # Event-triggered rules need external push, not scanning
        :skip

      "condition" ->
        case condition_met?(rule.trigger_config || %{}) do
          {:ok, true} ->
            if fire_already_this_minute?(rule, now) do
              :skip
            else
              {:fire,
               %{
                 next_fire_at: rule.next_fire_at,
                 trigger_info: %{"condition" => rule.trigger_config || %{}}
               }}
            end

          {:ok, false} ->
            :skip

          {:error, reason} ->
            Logger.warning(
              "Automation.Engine: condition rule #{rule.id} skipped: #{inspect(reason)}"
            )

            :skip
        end

      _ ->
        :skip
    end
  end

  defp fire_rule(rule, now, context, runner) do
    action_type = rule.action_type || "run_query"

    dispatch_result =
      case action_type do
        "create_task" ->
          create_task_from_schedule(rule, context)

        "run_query" ->
          run_query_from_schedule(rule, context, runner)

        "send_notification" ->
          Bus.publish(%{
            type: :automation_notification,
            schedule_id: rule.id,
            rule_id: rule.id,
            title: config_value(rule, "title") || rule.name,
            message: config_value(rule, "message") || config_value(rule, "description")
          })

          {:ok, %{kind: :notification}}

        unknown ->
          {:error, "unknown action type: #{unknown}"}
      end

    next_fire = context[:next_fire_at]
    status = next_status(rule, next_fire, dispatch_result)

    rule
    |> Schedule.changeset(%{
      last_fired_at: now,
      next_fire_at: next_fire,
      last_result: format_last_result(dispatch_result),
      status: status
    })
    |> Repo.update!()

    # Return {:ok, rule} for success tracking, {:error, reason} for logging
    case dispatch_result do
      {:ok, _} ->
        {:ok, rule}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fire_already_this_minute?(rule, now) do
    case rule.last_fired_at do
      nil -> false
      last -> same_minute?(last, now)
    end
  end

  defp same_minute?(a, b) do
    a.year == b.year && a.month == b.month &&
      a.day == b.day && a.hour == b.hour &&
      a.minute == b.minute
  end

  defp calculate_next(cron, after_dt) do
    case Cron.next_fire(cron, after_dt) do
      {:ok, dt} -> dt
      {:error, :no_match} -> nil
    end
  end

  defp condition_met?(%{"type" => "always"}), do: {:ok, true}
  defp condition_met?(%{type: "always"}), do: {:ok, true}

  defp condition_met?(%{"type" => "file_exists", "path" => path}) when is_binary(path) do
    {:ok, File.exists?(Path.expand(path))}
  end

  defp condition_met?(%{type: "file_exists", path: path}) when is_binary(path) do
    {:ok, File.exists?(Path.expand(path))}
  end

  defp condition_met?(%{"type" => "file_missing", "path" => path}) when is_binary(path) do
    {:ok, not File.exists?(Path.expand(path))}
  end

  defp condition_met?(%{type: "file_missing", path: path}) when is_binary(path) do
    {:ok, not File.exists?(Path.expand(path))}
  end

  defp condition_met?(%{"type" => "env_equals", "name" => name, "value" => value})
       when is_binary(name) do
    {:ok, System.get_env(name) == to_string(value)}
  end

  defp condition_met?(%{type: "env_equals", name: name, value: value}) when is_binary(name) do
    {:ok, System.get_env(name) == to_string(value)}
  end

  defp condition_met?(%{"type" => type}), do: {:error, {:unsupported_condition, type}}
  defp condition_met?(%{type: type}), do: {:error, {:unsupported_condition, type}}
  defp condition_met?(_), do: {:error, :missing_condition_type}

  # ── Event-triggered Rules ───────────────────────────────

  defp fire_event_rules(event_type, event_data, runner) do
    rules =
      Repo.all(
        from(s in Schedule,
          where: s.status == "active" and s.trigger_type == "event"
        )
      )

    matching =
      Enum.filter(rules, fn rule ->
        configured_event = get_in(rule.trigger_config, ["event_type"])
        configured_event == event_type
      end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(matching, fn rule ->
      if fire_already_this_minute?(rule, now) do
        :skip
      else
        case fire_rule(
               rule,
               now,
               %{
                 next_fire_at: nil,
                 trigger_info: %{"event_type" => event_type, "event_data" => event_data}
               },
               runner
             ) do
          {:ok, _rule} ->
            Logger.debug("Automation: event rule #{rule.id} fired on #{event_type}")

          {:error, reason} ->
            Logger.error("Automation: event rule #{rule.id} failed: #{inspect(reason)}")
        end
      end
    end)

    :ok
  end

  defp create_task_from_schedule(rule, context) do
    title = config_value(rule, "title") || rule.name || "自动化任务"
    description = config_value(rule, "description") || config_value(rule, "message") || ""
    goal_id = config_value(rule, "goal_id")
    workspace_path = config_value(rule, "workspace_path")
    autonomy_level = config_value(rule, "autonomy_level") || 1

    case Tasks.create_task(%{
           title: title,
           description: description,
           status: "pending",
           required_skills: config_value(rule, "required_skills") || [],
           goal_id: goal_id,
           metadata: %{
             "trigger" => "schedule",
             "schedule_id" => rule.id,
             "rule_id" => rule.id,
             "trigger_info" => context[:trigger_info] || %{},
             "autonomy_level" => autonomy_level,
             "workspace_path" => workspace_path
           }
         }) do
      {:ok, task} ->
        notify_dispatcher(task.id)

        Bus.publish(%{
          type: :automation_triggered,
          rule_name: rule.name,
          rule_id: rule.id,
          schedule_id: rule.id,
          task_id: task.id
        })

        {:ok, %{kind: :task, task_id: task.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_query_from_schedule(rule, context, runner) do
    objective =
      config_value(rule, "prompt") ||
        config_value(rule, "description") ||
        config_value(rule, "message") ||
        "请检查项目进展并报告状态"

    title = config_value(rule, "title") || rule.name || "自动化任务"

    attrs = %{
      source_type: "schedule",
      source_id: rule.id,
      schedule_id: rule.id,
      goal_id: config_value(rule, "goal_id"),
      title: title,
      objective: objective,
      mode: "scheduled",
      autonomy_level: config_value(rule, "autonomy_level") || 1,
      workspace_path: config_value(rule, "workspace_path"),
      messages: [%{role: "user", content: objective}],
      metadata: %{
        "entrypoint" => "automation.engine",
        "schedule_id" => rule.id,
        "schedule_name" => rule.name,
        "goal_id" => config_value(rule, "goal_id"),
        "trigger_type" => rule.trigger_type,
        "trigger_info" => context[:trigger_info] || %{}
      },
      opts: [
        permission_mode: :approval_required,
        autonomy_allowed_tools: ["goal_task"],
        max_turns: config_value(rule, "max_turns") || 80,
        max_wall_time: config_value(rule, "max_wall_time") || 900
      ]
    }

    case runner.(attrs, attrs.opts) do
      {:ok, run_id} ->
        Bus.publish(%{
          type: :automation_triggered,
          rule_name: rule.name,
          rule_id: rule.id,
          schedule_id: rule.id,
          run_id: run_id
        })

        {:ok, %{kind: :run, run_id: run_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_runner(attrs, opts) do
    Orchestrator.start_async(attrs, opts)
  end

  defp config_value(rule, key) do
    config = rule.action_config || %{}
    Map.get(config, key) || Map.get(config, existing_atom(key))
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp notify_dispatcher(task_id) do
    if Process.whereis(AIBrain.Task.Dispatcher) do
      AIBrain.Task.Dispatcher.notify_pending(AIBrain.Task.Dispatcher, task_id)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp format_last_result({:ok, result}), do: Jason.encode!(result)
  defp format_last_result({:error, reason}), do: "error: #{inspect(reason)}"

  defp next_status(%{trigger_type: "time"}, nil, {:ok, _}), do: "completed"
  defp next_status(rule, _next_fire, _result), do: rule.status
end
