defmodule AIBrain.Tool.Builtin.GoalTaskTool do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Goal/task tool backed directly by the canonical Data modules.

  This tool is part of the unified agent loop: autonomous runs, scheduled runs,
  and interactive runs all create and update tasks through the same tables.
  """

  alias AIBrain.Data.{Goals, Interactions, Tasks}
  alias AIBrain.Interaction.Manager, as: InteractionManager

  def name, do: "goal_task"
  def read_only?, do: false
  def risk_category, do: :workspace_write

  def description do
    "Manage goals and tasks. Operations: " <>
      "create_goal, update_goal, get_goal, list_goals, " <>
      "create_task, update_task, get_task, list_tasks, update_task_status, " <>
      "record_goal_strategy"
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "operation" => %{
          "type" => "string",
          "enum" => ~w(create_goal update_goal get_goal list_goals
               create_task update_task get_task list_tasks update_task_status
               record_goal_strategy),
          "description" => "Operation to perform"
        },
        "goal_id" => %{"type" => "string"},
        "task_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "output" => %{"type" => "string", "description" => "Task result output"},
        "depends_on" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "List of task IDs this task depends on"
        },
        "priority" => %{"type" => "integer"},
        "autonomous" => %{
          "type" => "boolean",
          "description" => "Whether the goal may be reviewed by the background GoalDaemon"
        },
        "autonomy_level" => %{
          "type" => "integer",
          "description" =>
            "0 = manual only, higher values allow background review and task planning"
        },
        "metadata" => %{"type" => "object"},
        "current_assessment" => %{
          "type" => "string",
          "description" => "Concise current assessment for a long-term goal"
        },
        "next_actions" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Concrete next actions to pursue"
        },
        "blockers" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Known blockers or decisions needed"
        },
        "needs_owner_input" => %{
          "type" => "boolean",
          "description" => "Whether the owner must clarify, approve, or provide access"
        },
        "next_focus" => %{
          "type" => "string",
          "description" => "What the next autonomous review should focus on"
        },
        "review_after_seconds" => %{
          "type" => "integer",
          "description" => "Optional cooldown override for the next GoalDaemon review"
        },
        "materialize_next_actions" => %{
          "type" => "boolean",
          "description" =>
            "Whether to create trackable tasks from next_actions when no owner input is needed"
        }
      },
      "required" => ["operation"]
    }
  end

  def execute(%{"operation" => "create_goal"} = args, ctx), do: create_goal(args, ctx)
  def execute(%{"operation" => "update_goal"} = args, _ctx), do: update_goal(args)
  def execute(%{"operation" => "get_goal"} = args, _ctx), do: get_goal(args)
  def execute(%{"operation" => "list_goals"} = args, ctx), do: list_goals(args, ctx)
  def execute(%{"operation" => "create_task"} = args, ctx), do: create_task(args, ctx)
  def execute(%{"operation" => "update_task"} = args, ctx), do: update_task(args, ctx)
  def execute(%{"operation" => "get_task"} = args, _ctx), do: get_task(args)
  def execute(%{"operation" => "list_tasks"} = args, ctx), do: list_tasks(args, ctx)

  def execute(%{"operation" => "update_task_status"} = args, ctx),
    do: update_task_status(args, ctx)

  def execute(%{"operation" => "record_goal_strategy"} = args, ctx),
    do: record_goal_strategy(args, ctx)

  def execute(%{"operation" => op}, _ctx), do: {:error, "Unknown operation: #{op}"}

  def execute(args, _ctx),
    do: {:error, "Missing required 'operation' field. Got: #{inspect(args)}"}

  defp create_goal(args, ctx) do
    with {:ok, title} <- require_string(args, "title") do
      metadata =
        args
        |> Map.get("metadata", %{})
        |> normalize_metadata()
        |> maybe_put("autonomous", Map.get(args, "autonomous"))
        |> maybe_put("autonomy_level", Map.get(args, "autonomy_level"))
        |> maybe_put("created_by_run_id", context_value(ctx, :run_id))
        |> maybe_put("created_by_source_type", context_value(ctx, :source_type))

      attrs =
        %{
          title: title,
          description: Map.get(args, "description", ""),
          priority: Map.get(args, "priority", 3),
          metadata: metadata
        }
        |> maybe_put(
          :workspace_path,
          context_value(ctx, :workspace_path) || context_value(ctx, :cwd)
        )

      case Goals.create(attrs) do
        {:ok, goal} ->
          {:ok,
           json(%{
             goal_id: goal.id,
             title: goal.title,
             status: goal.status,
             autonomy_level: metadata["autonomy_level"] || 0
           })}

        {:error, reason} ->
          {:error, "Failed to create goal: #{inspect(reason)}"}
      end
    end
  end

  defp update_goal(args) do
    with {:ok, id} <- require_string(args, "goal_id") do
      attrs =
        args
        |> map_attrs(~w(title description status priority))
        |> maybe_merge_metadata(args)

      case Goals.update(id, attrs) do
        {:ok, goal} ->
          {:ok, json(%{goal_id: goal.id, title: goal.title, status: goal.status})}

        {:error, :not_found} ->
          {:error, "Goal not found: #{id}"}

        {:error, reason} ->
          {:error, "Failed to update goal: #{inspect(reason)}"}
      end
    end
  end

  defp get_goal(args) do
    with {:ok, id} <- require_string(args, "goal_id") do
      case Goals.get(id) do
        {:ok, goal} ->
          {:ok,
           json(%{
             goal_id: goal.id,
             title: goal.title,
             description: goal.description,
             status: goal.status,
             priority: goal.priority,
             metadata: goal.metadata,
             workspace_path: goal.workspace_path
           })}

        {:error, :not_found} ->
          {:error, "Goal not found: #{id}"}
      end
    end
  end

  defp list_goals(args, ctx) do
    opts = []
    opts = if status = Map.get(args, "status"), do: Keyword.put(opts, :status, status), else: opts

    opts =
      case context_value(ctx, :workspace_path) || context_value(ctx, :cwd) do
        nil -> opts
        path -> Keyword.put(opts, :workspace_path, path)
      end

    with {:ok, goals} <- Goals.list(opts) do
      result =
        Enum.map(goals, fn goal ->
          %{
            goal_id: goal.id,
            title: goal.title,
            status: goal.status,
            priority: goal.priority,
            autonomy_level: (goal.metadata || %{})["autonomy_level"] || 0
          }
        end)

      {:ok, json(result)}
    end
  end

  defp create_task(args, ctx) do
    with {:ok, title} <- require_string(args, "title") do
      goal_id = Map.get(args, "goal_id") || context_value(ctx, :goal_id)
      run_id = context_value(ctx, :run_id)

      metadata =
        args
        |> Map.get("metadata", %{})
        |> normalize_metadata()
        |> maybe_put("created_by_run_id", run_id)
        |> maybe_put("created_by_source_type", context_value(ctx, :source_type))
        |> maybe_put("source_task_id", context_value(ctx, :task_id))
        |> maybe_put("schedule_id", context_value(ctx, :schedule_id))
        |> maybe_put(
          "workspace_path",
          context_value(ctx, :workspace_path) || context_value(ctx, :cwd)
        )
        |> maybe_put("autonomy_level", context_value(ctx, :autonomy_level))

      attrs = %{
        title: title,
        description: Map.get(args, "description", ""),
        goal_id: goal_id,
        depends_on: Map.get(args, "depends_on", []),
        priority: Map.get(args, "priority", 3),
        metadata: metadata
      }

      case Tasks.create_task(attrs) do
        {:ok, task} ->
          notify_pending(task.id)

          {:ok,
           json(%{
             task_id: task.id,
             title: task.title,
             status: task.status,
             goal_id: task.goal_id,
             depends_on: task.depends_on,
             created_by_run_id: run_id
           })}

        {:error, changeset} ->
          {:error, "Failed to create task: #{inspect(changeset.errors)}"}
      end
    end
  end

  defp update_task(args, ctx) do
    with {:ok, id} <- require_string(args, "task_id"),
         {:ok, task} <- Tasks.get_task(id) do
      attrs =
        args
        |> map_attrs(~w(title description status priority depends_on))
        |> maybe_merge_metadata(args)

      task_result =
        task
        |> maybe_link_run(context_value(ctx, :run_id))
        |> then(fn
          {:ok, linked_task} -> Tasks.update_task(linked_task, attrs)
          error -> error
        end)

      case task_result do
        {:ok, task} ->
          result =
            if Map.has_key?(args, "output") do
              Tasks.update_task_result(task, task.status, Map.get(args, "output"))
            else
              {:ok, task}
            end

          case result do
            {:ok, task} ->
              if task.status == "pending", do: notify_pending(task.id)
              {:ok, json(%{task_id: task.id, title: task.title, status: task.status})}

            {:error, changeset} ->
              {:error, "Failed to update task output: #{inspect(changeset.errors)}"}
          end

        {:error, changeset} ->
          {:error, "Failed to update task: #{inspect(changeset.errors)}"}
      end
    else
      {:error, :not_found} -> {:error, "Task not found: #{Map.get(args, "task_id")}"}
      error -> error
    end
  end

  defp get_task(args) do
    with {:ok, id} <- require_string(args, "task_id") do
      case Tasks.get_task(id) do
        {:ok, task} ->
          {:ok,
           json(%{
             task_id: task.id,
             title: task.title,
             description: task.description,
             status: task.status,
             goal_id: task.goal_id,
             depends_on: task.depends_on,
             output: task.output,
             run_id: task.run_id,
             metadata: task.metadata
           })}

        {:error, :not_found} ->
          {:error, "Task not found: #{id}"}
      end
    end
  end

  defp list_tasks(args, ctx) do
    goal_id = Map.get(args, "goal_id") || context_value(ctx, :goal_id)

    if is_binary(goal_id) and goal_id != "" do
      tasks = Tasks.list_tasks(goal_id)

      result =
        Enum.map(tasks, fn task ->
          %{
            task_id: task.id,
            title: task.title,
            status: task.status,
            depends_on: task.depends_on,
            run_id: task.run_id
          }
        end)

      {:ok, json(result)}
    else
      {:error, "Missing required 'goal_id' and no goal_id in run context"}
    end
  end

  defp update_task_status(args, ctx) do
    with {:ok, id} <- require_string(args, "task_id"),
         {:ok, status} <- require_string(args, "status"),
         {:ok, task} <- Tasks.get_task(id) do
      task_result = maybe_link_run(task, context_value(ctx, :run_id))

      result =
        with {:ok, linked_task} <- task_result do
          if Map.has_key?(args, "output") do
            Tasks.update_task_result(linked_task, status, Map.get(args, "output"))
          else
            Tasks.update_task(linked_task, %{status: status})
          end
        end

      case result do
        {:ok, task} ->
          if task.status == "pending", do: notify_pending(task.id)
          {:ok, json(%{task_id: task.id, status: task.status})}

        {:error, changeset} ->
          {:error, "Failed to update task: #{inspect(changeset.errors)}"}
      end
    else
      {:error, :not_found} -> {:error, "Task not found: #{Map.get(args, "task_id")}"}
      error -> error
    end
  end

  defp record_goal_strategy(args, ctx) do
    goal_id = Map.get(args, "goal_id") || context_value(ctx, :goal_id)
    run_id = context_value(ctx, :run_id)

    with {:ok, goal_id} <- require_value(goal_id, "goal_id"),
         {:ok, goal} <- Goals.get(goal_id) do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      strategy =
        %{
          "current_assessment" => Map.get(args, "current_assessment", ""),
          "next_actions" => normalize_string_list(Map.get(args, "next_actions", [])),
          "blockers" => normalize_string_list(Map.get(args, "blockers", [])),
          "needs_owner_input" => Map.get(args, "needs_owner_input", false) == true,
          "next_focus" => Map.get(args, "next_focus", ""),
          "updated_at" => now,
          "updated_by_run_id" => run_id
        }
        |> drop_blank_values()

      owner_interaction_id = maybe_request_owner_input(goal, args, ctx, strategy)
      task_plan = maybe_materialize_next_actions(goal, args, ctx, strategy)

      metadata =
        goal.metadata
        |> normalize_metadata()
        |> Map.put("strategy", strategy)
        |> maybe_put("last_strategy_run_id", run_id)
        |> maybe_put("last_strategy_updated_at", now)
        |> maybe_put("next_review_after", next_review_after(args))
        |> maybe_put("last_owner_interaction_id", owner_interaction_id)
        |> maybe_put(
          "last_owner_interaction_requested_at",
          if(owner_interaction_id, do: now)
        )
        |> Map.merge(%{
          "current_strategy" => Map.get(strategy, "current_assessment", ""),
          "next_actions" => Map.get(strategy, "next_actions", []),
          "blockers" => Map.get(strategy, "blockers", []),
          "needs_owner_input" => Map.get(strategy, "needs_owner_input", false),
          "last_report" => now
        })

      case Goals.update(goal.id, %{metadata: metadata}) do
        {:ok, updated} ->
          {:ok,
           json(%{
             goal_id: updated.id,
             strategy: strategy,
             owner_interaction_id: owner_interaction_id,
             tasks: task_plan,
             next_review_after: metadata["next_review_after"]
           })}

        {:error, reason} ->
          {:error, "Failed to record goal strategy: #{inspect(reason)}"}
      end
    else
      {:error, :not_found} -> {:error, "Goal not found: #{goal_id}"}
      error -> error
    end
  end

  defp maybe_request_owner_input(goal, args, ctx, strategy) do
    if strategy["needs_owner_input"] == true do
      existing_owner_interaction(goal) ||
        create_owner_interaction(goal, args, ctx, strategy)
    end
  end

  defp existing_owner_interaction(goal) do
    interaction_id = get_in(goal.metadata || %{}, ["last_owner_interaction_id"])

    case interaction_id && Interactions.get(interaction_id) do
      %{status: status} when status in ~w(pending proxy_running need_manual) -> interaction_id
      _ -> nil
    end
  end

  defp create_owner_interaction(goal, args, ctx, strategy) do
    if Process.whereis(InteractionManager) do
      schema = %{
        "title" => "Goal needs owner input: #{goal.title}",
        "prompt" => owner_prompt(goal, strategy),
        "fields" => [
          %{
            "name" => "response",
            "type" => "text",
            "label" => "Owner response",
            "required" => true
          },
          %{
            "name" => "decision",
            "type" => "select",
            "label" => "Decision",
            "options" => ["continue", "pause_goal", "revise_strategy"]
          }
        ]
      }

      context = %{
        "kind" => "goal_owner_input",
        "goal_id" => goal.id,
        "goal_title" => goal.title,
        "run_id" => context_value(ctx, :run_id),
        "source_type" => context_value(ctx, :source_type),
        "next_actions" => strategy["next_actions"] || [],
        "blockers" => strategy["blockers"] || [],
        "next_focus" => strategy["next_focus"],
        "requested_by_operation" => Map.get(args, "operation")
      }

      case InteractionManager.request(:form, schema, context,
             expires_in: Map.get(args, "owner_input_expires_in", 86_400)
           ) do
        {:ok, interaction_id} -> interaction_id
        {:error, _reason} -> nil
      end
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp owner_prompt(goal, strategy) do
    blockers = strategy["blockers"] || []
    next_actions = strategy["next_actions"] || []

    """
    长期目标「#{goal.title}」需要你的输入才能继续推进。

    当前判断：#{strategy["current_assessment"] || "未提供"}
    阻塞点：#{list_text(blockers)}
    建议下一步：#{list_text(next_actions)}
    下次关注：#{strategy["next_focus"] || "未提供"}
    """
  end

  defp list_text([]), do: "无"

  defp list_text(items) do
    items
    |> Enum.map(&"- #{&1}")
    |> Enum.join("\n")
  end

  defp maybe_materialize_next_actions(goal, args, ctx, strategy) do
    cond do
      Map.get(args, "materialize_next_actions", true) == false ->
        %{"created" => [], "existing" => [], "skipped" => "disabled"}

      strategy["needs_owner_input"] == true ->
        %{"created" => [], "existing" => [], "skipped" => "needs_owner_input"}

      true ->
        materialize_next_actions(goal, args, ctx, strategy)
    end
  end

  defp materialize_next_actions(goal, args, ctx, strategy) do
    existing_tasks = Tasks.list_tasks(goal.id)

    existing_by_key =
      existing_tasks
      |> Enum.reject(&(&1.status in ~w(cancelled failed)))
      |> Map.new(fn task -> {get_in(task.metadata || %{}, ["strategy_action_key"]), task} end)
      |> Map.delete(nil)

    strategy
    |> Map.get("next_actions", [])
    |> Enum.reduce(%{"created" => [], "existing" => [], "skipped" => nil}, fn action, acc ->
      key = strategy_action_key(goal.id, action)

      case Map.get(existing_by_key, key) do
        %{id: task_id} ->
          update_in(acc["existing"], &[task_id | &1])

        nil ->
          case create_strategy_task(goal, action, key, args, ctx, strategy) do
            {:ok, task} ->
              notify_pending(task.id)
              update_in(acc["created"], &[task.id | &1])

            {:error, reason} ->
              Map.update(acc, "errors", [reason], &[reason | &1])
          end
      end
    end)
    |> normalize_task_plan()
  end

  defp create_strategy_task(goal, action, key, args, ctx, strategy) do
    run_id = context_value(ctx, :run_id)

    metadata =
      %{
        "origin" => "goal_strategy",
        "strategy_action_key" => key,
        "created_by_run_id" => run_id,
        "created_by_source_type" => context_value(ctx, :source_type),
        "workspace_path" => goal.workspace_path,
        "autonomy_level" => get_in(goal.metadata || %{}, ["autonomy_level"]),
        "goal_strategy_updated_at" => strategy["updated_at"],
        "goal_strategy_focus" => strategy["next_focus"]
      }
      |> drop_blank_values()

    Tasks.create_task(%{
      title: action,
      description: "Generated from long-term goal strategy for: #{goal.title}",
      goal_id: goal.id,
      priority: Map.get(args, "priority", goal.priority || 3),
      metadata: metadata
    })
  end

  defp normalize_task_plan(plan) do
    plan
    |> Map.update!("created", &Enum.reverse/1)
    |> Map.update!("existing", &Enum.reverse/1)
    |> Map.update("errors", [], &Enum.reverse/1)
  end

  defp strategy_action_key(goal_id, action) do
    normalized =
      action
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")

    :crypto.hash(:sha256, "#{goal_id}:#{normalized}")
    |> Base.encode16(case: :lower)
  end

  defp maybe_link_run(task, nil), do: {:ok, task}

  defp maybe_link_run(%{run_id: run_id} = task, _run_id) when is_binary(run_id) and run_id != "",
    do: {:ok, task}

  defp maybe_link_run(task, run_id) when is_binary(run_id) and run_id != "" do
    Tasks.update_task(task, %{run_id: run_id})
  end

  defp require_string(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "Missing required '#{key}'"}
    end
  end

  defp require_value(value, _key) when is_binary(value) and value != "", do: {:ok, value}
  defp require_value(_value, key), do: {:error, "Missing required '#{key}'"}

  defp map_attrs(args, keys) do
    for key <- keys,
        Map.has_key?(args, key),
        into: %{} do
      {String.to_atom(key), args[key]}
    end
  end

  defp maybe_merge_metadata(attrs, args) do
    if Map.has_key?(args, "metadata"),
      do: Map.put(attrs, :metadata, normalize_metadata(args["metadata"])),
      else: attrs
  end

  defp normalize_metadata(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), val} end)
  end

  defp normalize_metadata(_value), do: %{}

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_string_list(_value), do: []

  defp drop_blank_values(map) do
    Map.reject(map, fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, []} -> true
      _pair -> false
    end)
  end

  defp next_review_after(args) do
    case Map.get(args, "review_after_seconds") do
      seconds when is_integer(seconds) and seconds > 0 ->
        DateTime.utc_now()
        |> DateTime.add(seconds, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      _ ->
        nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp context_value(ctx, key) when is_map(ctx) do
    Map.get(ctx, key) || Map.get(ctx, to_string(key))
  end

  defp context_value(_ctx, _key), do: nil

  defp notify_pending(task_id) do
    if Process.whereis(AIBrain.Task.Dispatcher) do
      AIBrain.Task.Dispatcher.notify_pending(AIBrain.Task.Dispatcher, task_id)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp json(value), do: Jason.encode!(value)
end
