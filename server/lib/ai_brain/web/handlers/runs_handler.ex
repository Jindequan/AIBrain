defmodule AIBrain.Web.Handlers.RunsHandler do
  import Plug.Conn

  alias AIBrain.AgentRuntime.{Evidence, FileStore, Orchestrator, RunLifecycle}
  alias AIBrain.Data.{Runs, RunSteps}

  def handle_list(conn, params) do
    opts =
      []
      |> maybe_put(:status, parse_status(params["status"]))
      |> maybe_put(:source_type, params["source_type"])
      |> maybe_put(:source_id, params["source_id"])
      |> maybe_put(:ref_type, params["ref_type"])
      |> maybe_put(:ref_id, params["ref_id"])
      |> maybe_put(:mode, params["mode"])
      |> maybe_put(:phase, params["phase"])
      |> maybe_put(:limit, parse_int(params["limit"]))

    runs = Runs.list_runs(opts)
    json(conn, 200, %{runs: Enum.map(runs, &serialize_run/1)})
  end

  def handle_get(conn, id) do
    case Runs.get_run(id) do
      {:ok, run} ->
        context = Runs.load_context(id)
        json(conn, 200, %{run: serialize_run(run), context: context})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_create(conn, params) do
    objective = params["objective"] || params["task"] || params["input"]

    cond do
      not is_binary(objective) or String.trim(objective) == "" ->
        json(conn, 400, %{error: "Missing objective"})

      true ->
        case Orchestrator.start_async(%{
               source_type: params["source_type"] || "manual",
               source_id: params["source_id"],
               objective: objective,
               title: params["title"] || objective,
               mode: params["mode"] || "manual",
               messages: [%{role: "user", content: objective}],
               metadata: params["metadata"] || %{},
               opts: []
             }) do
          {:ok, run_id} ->
            json(conn, 201, %{run_id: run_id, status: "started"})

          error ->
            json(conn, 500, %{error: inspect(error)})
        end
    end
  end

  def handle_cancel(conn, id) do
    _ = AIBrain.Engine.Overseer.cancel_tx(AIBrain.Engine.Overseer, id)

    case Runs.get_run(id) do
      {:ok, run} when run.status in ~w(pending running waiting_approval waiting_assistant) ->
        RunLifecycle.cancel(id, %{source: "api.runs"})
        json(conn, 200, %{status: "cancelled", run_id: id})

      {:ok, run} ->
        json(conn, 409, %{error: "Run is already terminal", run_id: id, status: run.status})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_output(conn, id) do
    with {:ok, run} <- Runs.get_run(id),
         {:ok, output} <- FileStore.read_output(id) do
      json(conn, 200, %{
        run_id: id,
        output: output,
        output_path: run.output_path || FileStore.output_path(id),
        output_summary: run.output_summary
      })
    else
      {:error, :not_found} -> json(conn, 404, %{error: "Run output not found"})
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  def handle_messages(conn, id) do
    case Runs.get_run(id) do
      {:ok, _run} ->
        case FileStore.load_messages(id) do
          {:ok, messages} -> json(conn, 200, %{run_id: id, messages: messages})
          {:error, :not_found} -> json(conn, 200, %{run_id: id, messages: []})
          {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
        end

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_events(conn, id, _params) do
    case Runs.get_run(id) do
      {:ok, _run} ->
        case FileStore.load_events(id) do
          {:ok, events} -> json(conn, 200, %{run_id: id, events: events})
          {:error, :not_found} -> json(conn, 200, %{run_id: id, events: []})
          {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
        end

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_steps(conn, id, params) do
    case Runs.get_run(id) do
      {:ok, _run} ->
        steps = RunSteps.list_for_run(id)

        steps =
          cond do
            phase = params["phase"] -> Enum.filter(steps, &(&1.phase == phase))
            kind = params["kind"] -> Enum.filter(steps, &(&1.kind == kind))
            status = params["status"] -> Enum.filter(steps, &(&1.status == status))
            true -> steps
          end

        json(conn, 200, %{run_id: id, steps: Enum.map(steps, &serialize_step/1)})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_evidence(conn, id) do
    case Runs.get_run(id) do
      {:ok, _run} ->
        items = Evidence.list_for_run(id)
        json(conn, 200, %{run_id: id, evidence: Enum.map(items, &serialize_evidence/1)})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_verification(conn, id) do
    case Runs.get_run(id) do
      {:ok, run} ->
        verification = get_in(run.metadata || %{}, ["verification"])

        if verification do
          json(conn, 200, %{
            run_id: id,
            verification: %{
              status: verification["status"] || verification[:status],
              warnings: verification["warnings"] || verification[:warnings] || [],
              failures: verification["failures"] || verification[:failures] || [],
              unknowns: verification["unknowns"] || verification[:unknowns] || []
            }
          })
        else
          json(conn, 200, %{
            run_id: id,
            verification: nil,
            note: "Run has not been verified yet or verification was skipped."
          })
        end

      {:error, :not_found} ->
        json(conn, 404, %{error: "Run not found"})
    end
  end

  def handle_stats(conn, _params) do
    all_runs = Runs.list_runs(limit: 500)

    total = length(all_runs)

    by_status =
      all_runs
      |> Enum.group_by(& &1.status)
      |> Map.new(fn {status, runs} -> {status, length(runs)} end)

    by_mode =
      all_runs
      |> Enum.group_by(& &1.mode)
      |> Map.new(fn {mode, runs} -> {mode, length(runs)} end)

    recent_runs =
      all_runs
      |> Enum.take(20)
      |> Enum.map(
        &%{
          id: &1.id,
          status: &1.status,
          mode: &1.mode,
          objective: &1.objective,
          started_at: &1.started_at,
          completed_at: &1.completed_at
        }
      )

    json(conn, 200, %{
      total_runs: total,
      by_status: by_status,
      by_mode: by_mode,
      recent_runs: recent_runs
    })
  end

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end

  defp serialize_step(step) do
    %{
      step_index: step.step_index,
      phase: step.phase,
      status: step.status,
      kind: step.kind,
      title: step.title,
      summary: step.summary,
      error: step.error,
      output_path: step.output_path,
      started_at: step.started_at,
      completed_at: step.completed_at
    }
  end

  defp serialize_evidence(item) do
    %{
      id: item.id,
      claim: item.claim,
      source_type: item.source_type,
      tool_name: item.tool_name,
      source_uri: item.source_uri,
      source_title: item.source_title,
      confidence: item.confidence,
      status: item.status,
      inserted_at: item.inserted_at
    }
  end

  defp serialize_run(run) do
    %{
      id: run.id,
      run_id: run.id,
      source_type: run.source_type,
      source_id: run.source_id,
      status: run.status,
      phase: run.phase,
      mode: run.mode,
      title: run.title,
      objective: run.objective,
      autonomy_level: run.autonomy_level,
      workspace_path: run.workspace_path,
      messages_path: run.messages_path,
      output_path: run.output_path,
      output_summary: run.output_summary,
      error: run.error,
      parent_run_id: run.parent_run_id,
      metadata: run.metadata,
      deliverables: run.deliverables,
      started_at: run.started_at,
      completed_at: run.completed_at,
      inserted_at: run.inserted_at,
      updated_at: run.updated_at
    }
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_status(nil), do: nil
  defp parse_status(statuses) when is_list(statuses), do: statuses

  defp parse_status(statuses) when is_binary(statuses) do
    statuses
    |> String.split(",", trim: true)
    |> case do
      [one] -> one
      many -> many
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: nil
end
