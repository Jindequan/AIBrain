defmodule AIBrain.Channel.SessionChannel do
  @moduledoc """
  Session channel - clear data flow, explicit structures.

  ## Responsibilities

  - Couple channel consumer with query execution
  - Provide high-level session operations
  - NO opts guessing

  Runtime execution is delegated to `AIBrain.AgentRuntime.Orchestrator`.
  """

  alias AIBrain.Channel.{Consumer, Config}
  alias AIBrain.Session.Store.Memory
  alias AIBrain.AgentRuntime.Orchestrator
  alias AIBrain.Telemetry.Audit

  defstruct [:consumer]

  @type t :: %__MODULE__{
          consumer: pid()
        }

  @doc """
  Start a new session channel.
  """
  def start_link(opts \\ []) do
    with {:ok, consumer} <- Consumer.start_link(opts) do
      {:ok, %__MODULE__{consumer: consumer}}
    end
  end

  @doc """
  Run messages through the channel.
  """
  def run(%__MODULE__{consumer: consumer}, messages, opts) do
    config = Config.build(Keyword.put(opts, :consumer, consumer))
    Orchestrator.run_messages(messages, Config.to_runtime_opts(config))
  end

  @doc """
  Resume an existing session.
  """
  def resume(%__MODULE__{consumer: consumer}, session_id, opts)
      when is_binary(session_id) do
    config = Config.build(Keyword.put(opts, :consumer, consumer))
    Orchestrator.resume_session(session_id, Config.to_runtime_opts(config))
  end

  @doc """
  Get published messages from the consumer.
  """
  def published(%__MODULE__{consumer: consumer}) do
    Consumer.published(consumer)
  end

  @doc """
  Dispatch a request to the consumer.
  """
  def dispatch(%__MODULE__{consumer: consumer}, request, opts \\ []) do
    Consumer.dispatch(consumer, request, opts)
  end

  @doc """
  Query the consumer.
  """
  def query(%__MODULE__{} = channel, query_kind, payload \\ %{}, opts \\ [])
      when is_atom(query_kind) do
    dispatch(
      channel,
      %{
        schema_version: 1,
        query_kind: query_kind,
        payload: payload
      },
      opts
    )
  end

  @doc """
  Send a directive to the consumer.
  """
  def directive(%__MODULE__{} = channel, directive_kind, payload \\ %{}, opts \\ [])
      when is_atom(directive_kind) do
    dispatch(
      channel,
      %{
        schema_version: 1,
        directive_kind: directive_kind,
        payload: payload
      },
      opts
    )
  end

  @doc """
  Get session status.
  """
  def status(%__MODULE__{}, session_id, opts) when is_binary(session_id) do
    session_store = Keyword.fetch!(opts, :session_store)

    case Memory.load_session(session_store, session_id) do
      {:error, :not_found} ->
        {:error, :session_not_found}

      {:ok, session} ->
        {:ok,
         %{
           session_id: session.session_id,
           metadata: session.metadata
         }}
    end
  end

  @doc """
  Export session data.
  """
  def export(%__MODULE__{}, session_id, opts) when is_binary(session_id) do
    session_store = Keyword.fetch!(opts, :session_store)
    Audit.export_session(session_store, session_id, Keyword.get(opts, :audit_opts, []))
  end

  @doc """
  Schedule a wake-up task.
  """
  def schedule_wake(%__MODULE__{}, attrs, _opts \\ []) do
    attrs
    |> schedule_attrs()
    |> AIBrain.Data.Schedules.create_schedule()
  end

  @doc """
  Cancel a wake-up task.
  """
  def cancel_wake(%__MODULE__{}, item_id, _opts \\ []) do
    AIBrain.Data.Schedules.update_schedule(item_id, %{"status" => "cancelled"})
  end

  @doc """
  Get scheduler status.
  """
  def scheduler_status(%__MODULE__{} = channel, opts \\ []) do
    query(channel, :scheduler_status, %{}, opts)
  end

  @doc """
  Create a task.
  """
  def create_task(%__MODULE__{}, attrs, _opts \\ []) do
    attrs = normalize_task_attrs(attrs)

    with {:ok, task} <- AIBrain.Data.Tasks.create_task(attrs) do
      AIBrain.Task.Dispatcher.notify_pending(task.id)
      {:ok, task}
    end
  end

  @doc """
  Get task status.
  """
  def task_status(%__MODULE__{} = channel, task_id, opts \\ []) do
    query(
      channel,
      :task_status,
      %{task_id: task_id},
      opts
    )
  end

  @doc """
  List all tasks.
  """
  def task_list(%__MODULE__{} = channel, opts \\ []) do
    query(channel, :task_list, %{}, opts)
  end

  @doc """
  Stop a task.
  """
  def stop_task(%__MODULE__{}, task_id, _opts \\ []) do
    with {:ok, task} <- AIBrain.Data.Tasks.get_task(task_id),
         {:ok, updated} <- AIBrain.Data.Tasks.update_task(task, %{status: "cancelled"}) do
      if task.run_id do
        _ = AIBrain.Engine.Overseer.cancel_tx(AIBrain.Engine.Overseer, task.run_id)
        AIBrain.AgentRuntime.RunLifecycle.cancel(task.run_id, %{source: "channel.task"})
      end

      {:ok, updated}
    end
  end

  defp normalize_task_attrs(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    command = attrs["command"]
    title = attrs["title"] || attrs["description"] || command || "Channel task"

    metadata =
      attrs
      |> Map.get("metadata", %{})
      |> Map.put("source", "channel")
      |> maybe_put("command", command)
      |> maybe_put("type", attrs["type"])

    attrs
    |> Map.put("title", title)
    |> Map.put_new("description", attrs["description"] || command)
    |> Map.put("metadata", metadata)
    |> Map.delete("command")
    |> Map.delete("type")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp schedule_attrs(attrs) do
    type = Map.get(attrs, :type) || Map.get(attrs, "type") || :one_shot
    action = Map.get(attrs, :action) || Map.get(attrs, "action") || %{}

    case type do
      type when type in [:recurring, "recurring"] ->
        %{
          "name" => Map.get(attrs, :name) || Map.get(attrs, "name") || "Scheduled task",
          "trigger_type" => "cron",
          "trigger_config" => %{
            "cron" => Map.get(attrs, :cron_expression) || Map.get(attrs, "cron_expression")
          },
          "action_type" => Map.get(action, "type") || Map.get(action, :type) || "create_task",
          "action_config" => normalize_action(action),
          "next_fire_at" => Map.get(attrs, :next_fire_at) || Map.get(attrs, "next_fire_at"),
          "status" => "active"
        }

      _ ->
        %{
          "name" => Map.get(attrs, :name) || Map.get(attrs, "name") || "Scheduled task",
          "trigger_type" => "time",
          "trigger_config" => %{},
          "action_type" => Map.get(action, "type") || Map.get(action, :type) || "create_task",
          "action_config" => normalize_action(action),
          "next_fire_at" => Map.get(attrs, :trigger_at) || Map.get(attrs, "trigger_at"),
          "status" => "active"
        }
    end
  end

  defp normalize_action(action) when is_map(action) do
    %{
      "title" => Map.get(action, "title") || Map.get(action, :title),
      "description" =>
        Map.get(action, "description") || Map.get(action, :description) ||
          Map.get(action, "message") || Map.get(action, :message),
      "message" => Map.get(action, "message") || Map.get(action, :message)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_action(_), do: %{}
end
