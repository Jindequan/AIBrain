defmodule AIBrain.Web.Handlers.ActiveRunsHandler do
  @moduledoc """
  Returns live in-process state for all active runs:
  combines Overseer executor state with the unified `runs` table.
  """
  import Plug.Conn
  require Logger
  alias AIBrain.Data.Runs

  def handle_active(conn) do
    overseer_entries = safe_list_overseer()
    run_entries = safe_list_runs()

    merged =
      Enum.map(run_entries, fn run ->
        overseer = Enum.find(overseer_entries, fn {tx_id, _pid, _} -> tx_id == run.id end)

        %{
          run_id: run.id,
          status: run.status,
          phase: run.phase,
          mode: run.mode,
          source_type: run.source_type,
          source_id: run.source_id,
          title: run.title,
          objective: run.objective,
          started_at: run.started_at,
          inserted_at: run.inserted_at
        }
        |> Map.put(:executor_status, overseer_status(overseer))
        |> Map.put(:executor_pid, overseer_pid(overseer))
      end)

    json(conn, 200, %{
      active_runs: merged,
      executor_count: length(overseer_entries),
      run_count: length(run_entries)
    })
  end

  # ── Private ──

  defp safe_list_overseer do
    AIBrain.Engine.Overseer.list_active()
  rescue
    e ->
      Logger.warning(
        "ActiveRunsHandler: failed to list overseer entries: #{Exception.message(e)}"
      )

      []
  catch
    :exit, _ -> []
  end

  defp safe_list_runs do
    Runs.list_runs(status: ["running", "pending", "waiting_approval", "waiting_assistant"])
  rescue
    e ->
      Logger.warning("ActiveRunsHandler: failed to list runs: #{Exception.message(e)}")
      []
  catch
    :exit, _ -> []
  end

  defp overseer_status(nil), do: nil
  defp overseer_status({_id, _pid, status}), do: status

  defp overseer_pid(nil), do: nil
  defp overseer_pid({_id, pid, _status}), do: inspect(pid)

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
