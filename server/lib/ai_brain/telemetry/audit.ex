defmodule AIBrain.Telemetry.Audit do
  @moduledoc """
  Exports replayable session timelines with optional redaction.
  """

  alias AIBrain.Session.Store.Memory
  alias AIBrain.Permissions.Diagnostics, as: PermissionDiagnostics
  alias AIBrain.System.SandboxDiagnostics, as: SandboxDiagnostics

  def export_session(session_store, session_id, opts \\ []) do
    case Memory.load_session(session_store, session_id) do
      {:error, :not_found} ->
        {:error, :session_not_found}

      {:ok, session} ->
        # Use runtime_events for diagnostics and export (if available), otherwise fall back to events
        diagnostic_events = Map.get(session, :runtime_events, session.events)
        export_events = Map.get(session, :runtime_events, session.events)

        {:ok,
         %{
           session_id: session.session_id,
           metadata: session.metadata,
           operator_diagnostics: %{
             permissions: PermissionDiagnostics.summarize(diagnostic_events),
             sandbox: SandboxDiagnostics.summarize(diagnostic_events)
           },
           events: redact(export_events, opts),
           messages: redact(session.messages, opts)
         }}
    end
  end

  defp redact(term, opts) when is_list(term), do: Enum.map(term, &redact(&1, opts))

  defp redact(term, opts) when is_map(term) do
    redacted_keys = MapSet.new(Keyword.get(opts, :redact_keys, [:text, :content, :result]))

    Map.new(term, fn {key, value} ->
      if MapSet.member?(redacted_keys, key) do
        {key, "[REDACTED]"}
      else
        {key, redact(value, opts)}
      end
    end)
  end

  defp redact(term, _opts), do: term
end
