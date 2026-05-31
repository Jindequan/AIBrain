defmodule AIBrain.Web.Handlers.ArtifactHandler do
  import Plug.Conn
  require Logger
  alias AIBrain.Data.Artifacts
  alias AIBrain.Data.Runs

  def handle_list(conn, params) do
    opts =
      []
      |> maybe_put_opt(:run_id, params["run_id"])
      |> maybe_put_opt(:kind, params["kind"])

    artifacts =
      case params["session_id"] do
        nil ->
          {:ok, arts} = Artifacts.list(opts)
          arts

        session_id ->
          # Find all runs for this session, then collect their artifacts
          {:ok, runs} = Runs.list_runs(source_type: "session", source_id: session_id)
          run_ids = Enum.map(runs, & &1.id)

          {:ok, all_arts} = Artifacts.list(opts)

          # Filter to only artifacts belonging to this session's runs
          Enum.filter(all_arts, fn a -> a.run_id in run_ids end)
      end

    json(conn, 200, %{artifacts: artifacts})
  end

  def handle_get(conn, id) do
    case Artifacts.get(id) do
      {:ok, artifact} -> json(conn, 200, artifact)
      {:error, :not_found} -> json(conn, 404, %{error: "Artifact not found"})
    end
  end

  def handle_create(conn, params) do
    case Artifacts.create(params) do
      {:ok, artifact} -> json(conn, 201, artifact)
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_update(conn, id, params) do
    case Artifacts.update(id, params) do
      {:ok, updated} -> json(conn, 200, updated)
      {:error, :not_found} -> json(conn, 404, %{error: "Artifact not found"})
      {:error, reason} -> json(conn, 422, %{error: reason})
    end
  end

  def handle_delete(conn, id) do
    case Artifacts.delete(id) do
      :ok -> json(conn, 200, %{message: "Deleted"})
      {:error, :not_found} -> json(conn, 404, %{error: "Artifact not found"})
    end
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end
end
