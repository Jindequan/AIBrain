defmodule AIBrain.AgentRuntime.Orchestrator do
  @moduledoc """
  Run engine — all requests go through Run. Infrastructure scales by mode.

  Flow:
      messages → RunRequest → RunLifecycle.create → execute → complete

  Interactive chat runs are lightweight: no file directories, no step records on create.
  Background/scheduled runs get full file storage and crash recovery.
  """

  require Logger

  alias AIBrain.AgentRuntime.{AuthorizationWorkflow, FileStore, RunLifecycle, RunRequest, RunSink}
  alias AIBrain.Data.RunSteps
  alias AIBrain.Engine.{Overseer, Transaction}

  @default_max_turns 200
  @default_max_wall_time 1800

  # ── Public API ──

  def run_messages(messages, opts \\ [], attrs \\ %{}) when is_list(messages) and is_map(attrs) do
    case run_messages_with_run(messages, opts, attrs) do
      {:ok, %{result: result}} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def run_messages_auto(messages, opts \\ [], attrs \\ %{})
      when is_list(messages) and is_map(attrs) do
    run_messages_with_run(messages, opts, attrs)
  end

  def run_messages_with_run(messages, opts \\ [], attrs \\ %{})
      when is_list(messages) and is_map(attrs) do
    {session_id, execution_messages} = chat_execution_messages(messages, opts, attrs)

    request_attrs =
      %{
        source_type: "chat",
        source_id: session_id,
        session_id: session_id,
        thread_id: session_id,
        objective: latest_user_text(execution_messages) || "User query",
        mode: Keyword.get(opts, :mode, "interactive"),
        workspace_path: Keyword.get(opts, :workspace_path),
        autonomy_level: Keyword.get(opts, :autonomy_level, 0),
        model: attrs[:model] || Keyword.get(opts, :model),
        messages: execution_messages,
        opts: opts
      }
      |> Map.merge(attrs)

    start(request_attrs, opts)
  end

  def resume_session(session_id, opts \\ []) when is_binary(session_id) do
    case resume_session_with_run(session_id, opts) do
      {:ok, %{result: result}} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def resume_session_with_run(session_id, opts \\ []) when is_binary(session_id) do
    session_store = Keyword.fetch!(opts, :session_store)

    case load_session(session_store, session_id) do
      {:error, :not_found} ->
        {:error, :session_not_found}

      {:ok, session} ->
        run_messages_with_run(session.messages, Keyword.put(opts, :_history_loaded, true), %{
          session_id: session_id
        })
    end
  end

  def resume_session_auto(session_id, opts \\ []) when is_binary(session_id) do
    resume_session_with_run(session_id, opts)
  end

  defp load_session(store, session_id) when is_atom(store) do
    store.load_session(store, session_id)
  end

  defp load_session(store, session_id) do
    AIBrain.Session.Store.Memory.load_session(store, session_id)
  end

  defp load_history_messages(store, session_id, new_messages) when is_atom(store) do
    case store.load_session(store, session_id) do
      {:ok, %{messages: existing}} when existing != [] -> existing ++ new_messages
      _ -> load_from_conversation_log(session_id, new_messages)
    end
  end

  defp load_history_messages(store, session_id, new_messages) do
    case AIBrain.Session.Store.Memory.load_session(store, session_id) do
      {:ok, %{messages: existing}} when existing != [] -> existing ++ new_messages
      _ -> load_from_conversation_log(session_id, new_messages)
    end
  end

  defp load_from_conversation_log(session_id, new_messages) do
    case AIBrain.ConversationLog.load_conversation(session_id) do
      {:ok, log_messages, _meta} when log_messages != [] ->
        # Avoid duplicating messages that already exist in the log.
        AIBrain.Session.HistoryMerge.merge(log_messages, new_messages)

      _ ->
        new_messages
    end
  end

  # ── start / start_async ──

  def start(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, request} <- RunRequest.new(attrs),
         {:ok, run} <- RunLifecycle.create(request) do
      case execute(run.id, request, opts) do
        {:ok, result} -> {:ok, %{run_id: run.id, result: result}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def start_async(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, request} <- RunRequest.new(attrs),
         {:ok, run} <- RunLifecycle.create(request) do
      notify = Keyword.get(opts, :notify) || get_in(request.opts, [:notify])

      run_id_ref = run.id

      Task.Supervisor.start_child(AIBrain.TaskSupervisor, fn ->
        result =
          case execute(run_id_ref, request, opts) do
            {:ok, result} -> result
            {:error, reason} -> {:error, reason}
          end

        if notify, do: send(notify, {:run_complete, run_id_ref, result})
      end)

      {:ok, run.id}
    end
  end

  # ── Execute ──

  defp execute(run_id, request, opts) do
    with :ok <- RunLifecycle.start(run_id, request) do
      do_execute(run_id, request, opts)
    end
  end

  defp do_execute(run_id, request, opts) do
    step =
      RunLifecycle.step(run_id, "executing", "running", "llm", "Agent transaction", %{
        summary: "LLM/tool transaction started."
      })

    tx =
      Transaction.new(
        :run,
        run_id,
        request.messages,
        tools(opts),
        max_turns: Keyword.get(opts, :max_turns, @default_max_turns),
        max_wall_time: Keyword.get(opts, :max_wall_time, @default_max_wall_time),
        parent_id: request.parent_run_id,
        model: Keyword.get(opts, :model)
      )

    ctx = engine_context(run_id, request, opts)

    case Overseer.start_transaction(Keyword.get(opts, :overseer, Overseer), tx, RunSink, ctx) do
      {:ok, executor_pid} ->
        await_result(
          run_id,
          executor_pid,
          request,
          step && step.id,
          Keyword.get(opts, :timeout, 300_000),
          Keyword.get(opts, :overseer, Overseer)
        )

      {:error, reason} ->
        error = RunLifecycle.stringify(reason)
        if step, do: RunSteps.fail(step.id, error)
        persist_session_failure(reason, request)
        RunLifecycle.fail(run_id, reason, request)
        {:error, reason}
    end
  end

  defp await_result(run_id, executor_pid, request, step_id, timeout, overseer) do
    monitor = Process.monitor(executor_pid)

    receive do
      {:transaction_complete, ^run_id, result} ->
        Process.demonitor(monitor, [:flush])
        complete(run_id, result, request, step_id)
        {:ok, result}

      {:DOWN, ^monitor, :process, ^executor_pid, reason} ->
        error = RunLifecycle.stringify({:process_exited, reason})
        if step_id, do: RunSteps.fail(step_id, error)
        persist_session_failure({:process_exited, reason}, request)
        RunLifecycle.fail(run_id, {:process_exited, reason}, request)
        {:error, {:process_exited, reason}}
    after
      timeout ->
        Process.demonitor(monitor, [:flush])
        Overseer.cancel_tx(overseer, run_id)
        error = "timeout"
        if step_id, do: RunSteps.fail(step_id, error)
        persist_session_failure(:timeout, request)
        RunLifecycle.fail(run_id, :timeout, request)
        {:error, :timeout}
    end
  end

  # ── Complete ──

  defp complete(run_id, result, request, step_id) do
    case result do
      {:ok, text, messages} ->
        if step_id,
          do:
            RunSteps.complete(step_id, %{
              summary: RunLifecycle.summarize(text),
              output_path: FileStore.output_path(run_id)
            })

        persist_session_response(result, request, messages)
        RunLifecycle.complete(run_id, text, request)

      {:error, reason} ->
        error = RunLifecycle.stringify(reason)
        if step_id, do: RunSteps.fail(step_id, error)
        persist_session_failure(reason, request)
        RunLifecycle.fail(run_id, reason, request)
    end
  end

  # ── Engine context ──

  defp engine_context(run_id, request, opts) do
    on_event = Keyword.get(opts, :on_event, fn _event -> :ok end)

    system =
      Keyword.get(opts, :system) || get_in(request.opts, [:system]) ||
        AIBrain.Prompts.build_system_prompt()

    %{
      router: Keyword.get(opts, :router, AIBrain.Provider.Router),
      executor: Keyword.get(opts, :executor, AIBrain.Tool.Executor),
      system: system,
      model: Keyword.get(opts, :model, get_in(request.opts, [:model])),
      http_client: Keyword.get(opts, :http_client, get_in(request.opts, [:http_client])),
      authorize_tool: AuthorizationWorkflow.authorize_tool(run_id, request, opts),
      on_event: fn event ->
        on_event.(event)
      end,
      caller: self(),
      caller_chain: [self() | Process.get(:"$callers", [])],
      context: %{
        run_id: run_id,
        session_id: request.session_id,
        goal_id: request.goal_id,
        task_id: request.task_id,
        cwd: request.workspace_path,
        workspace_path: request.workspace_path,
        autonomy_level: request.autonomy_level
      }
    }
  end

  # ── Tools ──

  defp tools(opts) do
    case Keyword.get(opts, :tools) do
      nil -> AIBrain.Tool.Registry.to_api_format(AIBrain.Tool.Registry)
      tools -> tools
    end
  rescue
    _ -> []
  end

  defp chat_execution_messages(messages, opts, attrs) do
    session_id = Keyword.get(opts, :session_id) || attrs[:session_id] || attrs["session_id"]
    history_loaded = Keyword.get(opts, :_history_loaded, false)
    source_type = attrs[:source_type] || attrs["source_type"] || "chat"
    is_chat = source_type == "chat"

    execution_messages =
      if is_chat and is_binary(session_id) and session_id != "" and not history_loaded do
        session_store = Keyword.get(opts, :session_store) || AIBrain.Config.session_store()
        load_history_messages(session_store, session_id, messages)
      else
        messages
      end

    {session_id, execution_messages}
  end

  # ── Session persistence ──

  defp persist_session_response(
         {:ok, text, _history},
         %{session_id: session_id} = request,
         messages
       )
       when is_binary(session_id) and session_id != "" and is_list(messages) do
    case last_assistant_message(messages, text) do
      %AIBrain.Message{role: "assistant"} = msg ->
        store = session_store_for(request)
        append_session_message(store, session_id, msg)
        maybe_rotate_session(store, session_id)

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("Orchestrator: failed to persist session response: #{Exception.message(e)}")
  end

  defp persist_session_response(_, _, _), do: :ok

  defp persist_session_failure(reason, %{session_id: session_id} = request)
       when is_binary(session_id) and session_id != "" do
    store = session_store_for(request)
    text = "I couldn't complete that request: #{AIBrain.Core.ErrorFormatter.format_en(reason)}"

    msg =
      AIBrain.Message.new("assistant",
        content: [%{type: "text", text: text}],
        metadata: %{
          "status" => "failed",
          "error" => RunLifecycle.stringify(reason)
        }
      )

    append_session_message(store, session_id, msg)
  rescue
    e ->
      Logger.warning("Orchestrator: failed to persist session failure: #{Exception.message(e)}")
  end

  defp persist_session_failure(_, _), do: :ok

  defp last_assistant_message(messages, fallback_text) do
    Enum.find(Enum.reverse(messages), fn
      %AIBrain.Message{role: "assistant"} -> true
      _ -> false
    end) || assistant_message_from_text(fallback_text)
  end

  defp assistant_message_from_text(text) when is_binary(text) and text != "" do
    AIBrain.Message.from_json(%{"role" => "assistant", "content" => text})
  end

  defp assistant_message_from_text(_), do: nil

  defp session_store_for(%{opts: opts}) when is_list(opts) do
    Keyword.get(opts, :session_store) || AIBrain.Config.session_store()
  end

  defp session_store_for(_), do: AIBrain.Config.session_store()

  defp append_session_message(store, session_id, message) when is_atom(store) do
    store.append_message(store, session_id, message)
  end

  defp append_session_message(store, session_id, message) do
    AIBrain.Session.Store.Memory.append_message(store, session_id, message)
  end

  defp maybe_rotate_session(store, session_id) when is_atom(store) do
    if function_exported?(store, :maybe_rotate, 2) do
      store.maybe_rotate(store, session_id)
    else
      :ok
    end
  end

  defp maybe_rotate_session(store, session_id) do
    AIBrain.Session.Store.Memory.maybe_rotate(store, session_id)
  end

  # ── Helpers ──

  defp latest_user_text(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "user", content: content} when is_binary(content) -> content
      %{"role" => "user", "content" => content} when is_binary(content) -> content
      %{role: "user", content: [%{type: "text", text: text} | _]} -> text
      %{"role" => "user", "content" => [%{"type" => "text", "text" => text} | _]} -> text
      _ -> nil
    end)
  end
end
