defmodule AIBrain.AgentRuntime.FileStore do
  @moduledoc """
  File paths and persistence for large run payloads.

  The runtime stores large texts, LLM transcripts, and output bodies on disk.
  Database rows should keep only state, short summaries, and these paths.
  """

  def run_dir(run_id) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join([data_dir, "runs", run_id])
  end

  def messages_path(run_id), do: Path.join(run_dir(run_id), "messages.jsonl")
  def events_path(run_id), do: Path.join(run_dir(run_id), "events.jsonl")
  def output_path(run_id), do: Path.join(run_dir(run_id), "output.md")

  def ensure_run_dir(run_id) do
    File.mkdir_p!(run_dir(run_id))
    :ok
  end

  def append_message(run_id, message) do
    AIBrain.MessageLog.append(messages_path(run_id), message)
  end

  def load_messages(run_id) do
    AIBrain.MessageLog.load(messages_path(run_id))
  end

  def append_event(run_id, event) when is_map(event) do
    path = events_path(run_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(normalize_event(event)) <> "\n", [:append])
    :ok
  rescue
    _ -> {:error, :append_failed}
  end

  def load_events(run_id) do
    AIBrain.MessageLog.load(events_path(run_id))
  end

  def read_output(run_id) do
    path = output_path(run_id)

    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def write_output(run_id, text) when is_binary(text) do
    path = output_path(run_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    {:ok, path}
  end

  defp normalize_event(event) do
    event
    |> normalize_value()
    |> Map.put_new("ts", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp normalize_value(%{} = value) do
    Map.new(value, fn {key, item} -> {to_string(key), normalize_value(item)} end)
  end

  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value) when is_tuple(value), do: inspect(value)
  defp normalize_value(value) when is_atom(value), do: to_string(value)
  defp normalize_value(value), do: value
end
