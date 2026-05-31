defmodule AIBrain.Engine.Executor do
  @moduledoc """
  Per-transaction GenServer that owns the lifecycle of one LLM transaction.

  Started dynamically under Overseer's DynamicSupervisor. Each Executor
  handles exactly one transaction. It spawns a worker process that runs
  the actual turn loop (SSE collection, tool execution). The Executor itself
  stays responsive for cancel/status queries.

  Restart strategy: `:temporary` -- never restarted by supervisor.
  """

  use GenServer, restart: :temporary
  require Logger

  alias AIBrain.Engine.Loop
  alias AIBrain.Core.Events

  # ── Client API ──

  @doc "Start an executor for a single transaction. Called by Overseer."
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Cancel this transaction. Kills the worker process."
  def cancel(pid) do
    GenServer.call(pid, :cancel)
  end

  @doc "Get current transaction status."
  def status(pid) do
    GenServer.call(pid, :status)
  end

  @doc "Get the transaction id for this executor."
  def tx_id(pid) do
    GenServer.call(pid, :tx_id)
  end

  # ── Callbacks ──

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    tx = opts[:tx]
    sink = opts[:sink]
    ctx = opts[:ctx]
    caller = opts[:caller]

    state = %{
      tx: tx,
      sink: sink,
      ctx: ctx,
      caller: caller,
      worker_pid: nil
    }

    if caller do
      Process.monitor(caller)
    end

    {:ok, state, {:continue, :spawn_worker}}
  end

  @impl true
  def handle_continue(:spawn_worker, state) do
    # Spawn a linked worker process to run the turn loop.
    # The Executor GenServer stays responsive for cancel/status calls
    # while the worker handles the (potentially long-running) LLM calls.
    # Set $callers so Mox can resolve mock expectations against the
    # caller process instead of requiring explicit Mox.allow per transaction.
    caller_chain = state.ctx[:caller_chain] || [state.caller]
    executor_pid = self()
    tx = state.tx
    sink = state.sink
    ctx = state.ctx

    worker_pid =
      spawn_link(fn ->
        Process.put(:"$callers", caller_chain)

        try do
          result = turn_loop(tx, sink, ctx, 0)
          send(executor_pid, {:worker_result, tx.id, result})
        rescue
          e ->
            Logger.error("Executor worker for #{tx.id} crashed: #{Exception.message(e)}")
            send(executor_pid, {:worker_result, tx.id, {:error, {:crash, Exception.message(e)}}})
        end
      end)

    {:noreply, %{state | worker_pid: worker_pid}}
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    if state.worker_pid && Process.alive?(state.worker_pid) do
      Process.exit(state.worker_pid, :kill)
    end

    tx = %{state.tx | status: :aborted, completed_at: DateTime.utc_now()}

    try do
      state.sink.save_result(tx.id, {:error, :cancelled})
    rescue
      _ -> :ok
    end

    send(state.caller, {:transaction_complete, tx.id, {:error, :cancelled}})

    {:stop, :normal, :ok, %{state | tx: tx}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {:ok, state.tx}, state}
  end

  @impl true
  def handle_call(:tx_id, _from, state) do
    {:reply, state.tx.id, state}
  end

  @impl true
  def handle_info({:worker_result, _tx_id, result}, state) do
    # Notify caller BEFORE saving to DB — the caller process (Runner) may
    # be the only process with sandbox access during testing, and save_result
    # can crash if the Executor doesn't own a DB connection.
    send(state.caller, {:transaction_complete, state.tx.id, result})

    try do
      state.sink.save_result(state.tx.id, result)
    rescue
      _ -> :ok
    end

    {:stop, :normal, %{state | tx: %{state.tx | status: :completed, result: result}}}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{worker_pid: pid} = state) do
    case reason do
      :normal ->
        {:noreply, state}

      :killed ->
        {:noreply, state}

      _ ->
        Logger.error("Executor worker for #{state.tx.id} crashed: #{inspect(reason)}")
        result = {:error, {:worker_crash, reason}}

        # Notify caller before DB save (same reason as worker_result handler)
        send(state.caller, {:transaction_complete, state.tx.id, result})

        try do
          state.sink.save_result(state.tx.id, result)
        rescue
          _ -> :ok
        end

        {:stop, :normal, %{state | tx: %{state.tx | status: :failed, result: result}}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{caller: pid} = state) do
    Logger.warning("Executor for #{state.tx.id}: caller #{inspect(pid)} died, cancelling")

    if state.worker_pid && Process.alive?(state.worker_pid) do
      Process.exit(state.worker_pid, :kill)
    end

    try do
      state.sink.save_result(state.tx.id, {:error, :caller_died})
    rescue
      _ -> :ok
    end

    {:stop, :normal,
     %{state | tx: %{state.tx | status: :aborted, completed_at: DateTime.utc_now()}}}
  end

  # ── Worker (runs inline in handle_continue) ──

  defp turn_loop(tx, sink, ctx, turn) do
    case Loop.check_limits(turn, tx.max_turns, tx.created_at, tx.max_wall_time) do
      {:stop, reason} ->
        {:error, reason}

      :continue ->
        case select_provider(ctx[:router], tx, turn, tx.retries) do
          {:error, reason} ->
            emit_provider_failed(ctx[:on_event], reason)
            {:error, reason}

          {:ok, provider, model_name} ->
            ctx = Map.put(ctx, :max_context_tokens, AIBrain.Provider.Info.model_context_window(provider, model_name))
            ctx = Map.put(ctx, :model, model_name)

            # Record the selected model in the transaction for later persistence
            tx = %{tx | model: model_name}

            messages =
              Loop.prepare_messages(
                tx.messages,
                ctx[:system] || "",
                nil,
                Keyword.take(Map.to_list(ctx), [:max_context_tokens, :on_event])
              )

            protocol = detect_protocol(provider)

            emit_provider_selected(ctx[:on_event], provider, protocol, model_name)

            on_event = ctx[:on_event] || fn _ -> :ok end

            wrapped_on_event = fn event ->
              emit_stream_event(event, on_event)
            end

            stream_opts =
              [
                system: ctx[:system] || "",
                model: model_name,
                on_event: wrapped_on_event,
                protocol: protocol
              ] ++
                if(ctx[:http_client], do: [http_client: ctx[:http_client]], else: [])

            case AIBrain.LLM.Client.stream(provider, messages, tx.tools, stream_opts) do
              {:ok, :streaming_complete} ->
                raw_events = collect_sse_events()
                response = AIBrain.LLM.SSE.Parser.collect_sse_events(raw_events)
                emit_turn_complete(on_event, response)
                handle_response(tx, sink, ctx, turn, response)

              {:error, :http, 429, headers, _body} ->
                # Put the provider in cooldown and retry with next provider.
                # If retry fails because all providers are in cooldown (only
                # the one that returned 429 was available), return :rate_limited.
                router = ctx[:router] || AIBrain.Provider.Router
                protocol = detect_protocol(provider)
                cool_until = parse_retry_after(headers)
                AIBrain.Provider.Router.set_cooldown(router, provider.name, protocol, cool_until)
                retry_tx = %{tx | retries: tx.retries + 1}

                case turn_loop(retry_tx, sink, ctx, turn) do
                  {:error, {:all_unavailable, _}} -> {:error, :rate_limited}
                  other -> other
                end

              {:error, :http, status, _headers, _body} when status >= 500 ->
                {:error, {:provider_error, status}}

              {:error, :http, status, _headers, _body} ->
                {:error, {:provider_error, "HTTP #{status}"}}

              {:error, :transport, _reason} ->
                {:error, :transport_error}

              {:error, reason, _detail} ->
                {:error, reason}
            end
        end
    end
  end

  defp handle_response(tx, sink, ctx, turn, response) do
    case response.stop_reason do
      :tool_call ->
        authorize = ctx[:authorize_tool] || fn tu -> {:allow, tu} end

        case Loop.execute_tools(
               response.tool_uses,
               ctx[:executor],
               ctx[:context] || %{},
               authorize
             ) do
          {:suspended, meta} ->
            {:suspended, meta}

          results ->
            emit_tool_results(results, ctx[:on_event], ctx[:persist_event])
            {new_messages, _} = Loop.merge_results(tx.messages, response, results)

            # Inject error recovery hint if any tool failed
            new_messages = maybe_inject_error_recovery(new_messages, results)

            # Compact tx.messages to prevent unbounded growth across turns.
            # ContextBudget ensures per-API-call compression, but the compressed
            # snapshot is ephemeral — tx.messages itself grows forever without
            # this explicit state compaction.
            new_messages = Loop.compact_state(new_messages, ctx)

            # Persist the assistant message (with tool results) after each turn.
            # Find the actual assistant message — NOT the error recovery hint.
            # The hint stays in new_messages for the next LLM turn but must not
            # be persisted as a conversation message.
            last_assistant =
              new_messages |> Enum.reverse() |> Enum.find(&(&1.role == "assistant"))

            if last_assistant, do: sink.save_message(tx.id, last_assistant)
            turn_loop(%{tx | messages: new_messages}, sink, ctx, turn + 1)
        end

      _ ->
        assistant_msg = %AIBrain.Message{role: "assistant", content: response.content}
        # Skip persisting empty responses
        if response.content != [] do
          sink.save_message(tx.id, assistant_msg)
        end

        {:ok, response.text, tx.messages ++ [assistant_msg]}
    end
  end

  # If any tool execution resulted in an error, inject a recovery hint
  # as a system message to guide the LLM toward retrying with a different approach.
  defp maybe_inject_error_recovery(messages, results) do
    has_errors =
      Enum.any?(results, fn
        {_, _, {:error, _}} -> true
        _ -> false
      end)

    if has_errors do
      error_names =
        results
        |> Enum.filter(fn {_, _, r} -> match?({:error, _}, r) end)
        |> Enum.map(fn {_, name, _} -> name end)
        |> Enum.uniq()

      hint =
        "[System: Tool execution failed for: #{Enum.join(error_names, ", ")}. " <>
          "Analyze the error output above and try an alternative approach. " <>
          "Do NOT repeat the same parameters.]"

      messages ++ [%AIBrain.Message{role: "system", content: hint}]
    else
      messages
    end
  end

  defp select_provider(nil, _tx, _turn, _retries) do
    AIBrain.Provider.Router.select(AIBrain.Provider.Router, type: :llm)
  end

  defp select_provider(router, %{model: model}, _turn, _retries)
       when is_binary(model) and model != "" do
    AIBrain.Provider.Router.select(router, model: model)
  end

  defp select_provider(router, _tx, _turn, _retries) do
    AIBrain.Provider.Router.select(router, type: :llm)
  end

  defp detect_protocol(provider) do
    proto =
      if is_map(provider) && Map.has_key?(provider, :protocol),
        do: provider.protocol,
        else: "openai"

    AIBrain.Provider.Router.normalize_protocol(proto)
  end

  defp collect_sse_events(acc \\ []) do
    receive do
      {:sse_event, event} -> collect_sse_events([event | acc])
      {:sse_done} -> Enum.reverse(acc)
    after
      60_000 -> Enum.reverse(acc)
    end
  end

  defp emit_tool_results(results, on_event, persist_event) do
    Enum.each(results, fn {id, _name, result} ->
      event = Events.tool_result(id, result)
      if persist_event, do: persist_event.(event)
      on_event.(event)
    end)
  end

  # ── Event helpers ──

  defp emit_stream_event({:text_delta, text}, on_event),
    do: on_event.(Events.text_delta(text))

  defp emit_stream_event({:thinking_start, %{index: index}}, on_event) do
    on_event.(Events.thinking_start(index))
  end

  defp emit_stream_event({:thinking_delta, %{index: index, text: text}}, on_event) do
    on_event.(Events.thinking_delta(index, text))
  end

  defp emit_stream_event({:thinking_end, %{index: index}}, on_event) do
    on_event.(Events.thinking_end(index))
  end

  defp emit_stream_event({:tool_use_start, %{index: index, id: id, name: name}}, on_event) do
    on_event.(%{
      type: :tool_use_start_sse,
      tool_use_index: index,
      tool_use_id: id,
      tool_name: name,
      input: nil
    })
  end

  defp emit_stream_event({:tool_use_complete, %{id: id, name: name, input: input}}, on_event) do
    on_event.(%{type: :tool_use_complete, tool_use_id: id, tool_name: name, input: input})
  end

  defp emit_stream_event(_event, _on_event), do: :ok

  defp emit_provider_selected(nil, _provider, _protocol, _model), do: :ok

  defp emit_provider_selected(on_event, provider, protocol, model) do
    resolved_model = AIBrain.LLM.Client.resolve_model(provider, model)

    on_event.(%{
      type: :provider_selected,
      provider_name: provider.name,
      protocol: protocol,
      model: resolved_model
    })
  end

  defp emit_turn_complete(nil, _response), do: :ok

  defp emit_turn_complete(on_event, response) do
    on_event.(%{type: :turn_complete, text: response.text, stop_reason: response.stop_reason})
  end

  defp emit_provider_failed(nil, _reason), do: :ok

  defp emit_provider_failed(on_event, reason) do
    on_event.(%{type: :provider_failed, reason: reason})
  end

  # ── Rate-limit / Retry helpers ──

  defp parse_retry_after(headers) when is_list(headers) do
    retry_after =
      case Enum.find(headers, fn {k, _v} -> String.downcase(k) == "retry-after" end) do
        {_, value} ->
          case Integer.parse(value) do
            {seconds, _} -> seconds
            :error -> 30
          end

        nil ->
          30
      end

    # Return seconds-since-epoch float to match Endpoint.retry_at format
    System.os_time(:millisecond) / 1000 + retry_after
  end

  defp parse_retry_after(_headers) do
    System.os_time(:millisecond) / 1000 + 30
  end
end
