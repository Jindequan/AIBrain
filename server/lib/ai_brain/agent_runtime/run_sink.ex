defmodule AIBrain.AgentRuntime.RunSink do
  @moduledoc """
  ResultSink for unified agent runtime runs.

  For runs with file storage, stores messages on disk.
  For inline runs (simple direct responses), skips file I/O entirely.
  """

  @behaviour AIBrain.Engine.ResultSink

  require Logger
  alias AIBrain.AgentRuntime.FileStore
  alias AIBrain.Data.Runs

  @impl true
  def save_message(run_id, message) do
    case Runs.get_run(run_id) do
      {:ok, %{messages_path: path}} when is_binary(path) ->
        FileStore.append_message(run_id, message)

      _ ->
        :ok
    end
  end

  @impl true
  def save_result(run_id, result) do
    case Runs.get_run(run_id) do
      {:ok, %{messages_path: path}} when is_binary(path) ->
        case result do
          {:ok, text, _messages} when is_binary(text) ->
            # Write output file for crash recovery. DB transition
            # is handled by Orchestrator via RunLifecycle.complete.
            FileStore.write_output(run_id, text)

          {:error, _reason} ->
            :ok

          {:suspended, _meta} ->
            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("RunSink: failed to save result for #{run_id}: #{Exception.message(e)}")
      :ok
  end

  @impl true
  def flush(_run_id), do: :ok

  @impl true
  def load(run_id), do: Runs.get_run(run_id)

  @impl true
  def list_running do
    Runs.list_runs(status: ["running", "pending", "waiting_approval", "waiting_assistant"])
    |> Enum.map(& &1.id)
  end
end
