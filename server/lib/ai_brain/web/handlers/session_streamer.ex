defmodule AIBrain.Web.Handlers.SessionStreamer do
  @moduledoc """
  Session streaming - SSE (Server-Sent Events) response.

  ## Responsibilities

  - Handle SSE streaming
  - NO request validation (done by Handler)
  - NO business logic (done by AgentRuntime.Orchestrator)

  ## Data Flow

      Request
        ↓
      setup_sse/2
        ↓
      stream_query/3
        ↓
      send_events/3
  """

  import Plug.Conn
  require Logger

  alias AIBrain.AgentRuntime.Orchestrator

  # Used: put_resp_content_type, put_resp_header, send_chunked, chunk

  @doc """
  Stream AI response via SSE.
  """
  def stream(conn, session_id, request) do
    conn = setup_sse(conn)

    on_event = build_event_handler(conn, make_ref())

    opts = build_query_opts(request, on_event)

    result = execute_query(session_id, request.messages, opts)

    finalize_stream(conn, result, session_id)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp setup_sse(conn) do
    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
  end

  defp build_event_handler(conn, disconnect_ref) do
    fn event ->
      if Process.get(:sse_disconnected) do
        :ok
      else
        data =
          %{
            type: event.type || "event",
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
            data: Map.delete(event, :__struct__)
          }
          |> Jason.encode!()

        case Plug.Conn.chunk(conn, "event: message\ndata: #{data}\n\n") do
          {:ok, _} ->
            :ok

          {:error, :closed} ->
            Process.put(:sse_disconnected, true)
            send(self(), {:sse_disconnect, disconnect_ref})
        end
      end
    end
  end

  defp build_query_opts(request, on_event) do
    [
      session_store: store(),
      on_event: on_event,
      model: request.model,
      mode: "interactive",
      style: request.mode,
      permission_mode: :approval_required,
      run_policy: :always
    ]
    |> add_workspace_path(request.workspace_path)
  end

  defp add_workspace_path(opts, nil), do: opts
  defp add_workspace_path(opts, path), do: Keyword.put(opts, :workspace_path, path)

  defp execute_query(session_id, _messages, opts) do
    Orchestrator.resume_session_auto(session_id, opts)
  end

  defp finalize_stream(conn, result, session_id) do
    # Client already disconnected — skip sending completion events
    if Process.get(:sse_disconnected) do
      conn
    else
      case result do
        {:ok, %{run_id: run_id, result: {:ok, text, _history}}} ->
          Plug.Conn.chunk(
            conn,
            sse_event("complete", %{response: text, session_id: session_id, run_id: run_id})
          )

          store().maybe_rotate(store(), session_id)

          conn

        {:ok, %{run_id: run_id, result: {:suspended, meta}}} ->
          Plug.Conn.chunk(
            conn,
            sse_event("suspended", %{
              session_id: session_id,
              run_id: run_id,
              suspended: true,
              status: Map.get(meta, :status, "waiting_approval"),
              reason: Map.get(meta, :reason, "approval_required"),
              interaction_id: Map.get(meta, :interaction_id),
              approval_id: Map.get(meta, :approval_id) || Map.get(meta, :interaction_id),
              tool_name: Map.get(meta, :tool_name)
            })
          )

          conn

        {:error, :session_not_found} ->
          Plug.Conn.chunk(
            conn,
            sse_event("error", %{error: "Session not found", session_id: session_id})
          )

          conn

        {:ok, %{run_id: run_id, result: {:error, reason}}} ->
          Logger.error("Session #{session_id} query error: #{inspect(reason)}")

          Plug.Conn.chunk(
            conn,
            sse_event("error", %{
              error: "Internal server error",
              session_id: session_id,
              run_id: run_id
            })
          )

          conn

        {:ok, %{run_id: run_id, result: {:error, _reason, _detail}}} ->
          Plug.Conn.chunk(
            conn,
            sse_event("error", %{
              error: "Service temporarily unavailable",
              session_id: session_id,
              run_id: run_id
            })
          )

          conn

        {:error, reason} ->
          Logger.error("Session #{session_id} query error: #{inspect(reason)}")

          Plug.Conn.chunk(
            conn,
            sse_event("error", %{error: "Internal server error", session_id: session_id})
          )

          conn

        {:error, _reason, _detail} ->
          Plug.Conn.chunk(
            conn,
            sse_event("error", %{error: "Service temporarily unavailable", session_id: session_id})
          )

          conn
      end
    end
  end

  defp sse_event(event, data) do
    "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
  end

  defp store, do: AIBrain.Config.session_store()
end
