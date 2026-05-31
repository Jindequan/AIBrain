defmodule AIBrain.MessageLog do
  @moduledoc """
  JSONL message log for all LLM flows. Append-only, one JSON object per line.
  Thread-safe: file append is atomic at the OS level for small writes.
  """

  require Logger

  @doc "Returns the standard JSONL path for messages. subdir is e.g. 'runs', 'plans', 'tasks'."
  def messages_path(subdir, id) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join([data_dir, subdir, id, "messages.jsonl"])
  end

  @doc """
  Append a single message to a JSONL file.
  Creates parent directories if needed. Returns :ok or {:error, reason}.
  """
  def append(path, message) do
    File.mkdir_p!(Path.dirname(path))
    entry = Jason.encode!(normalize(message)) <> "\n"
    File.write!(path, entry, [:append])
    :ok
  rescue
    e ->
      Logger.error("MessageLog.append failed for #{path}: #{Exception.message(e)}")
      {:error, :append_failed}
  end

  @doc """
  Load all messages from a JSONL file.
  Returns {:ok, [message]} or {:ok, []} if file doesn't exist.
  """
  def load(path) do
    case File.read(path) do
      {:ok, content} ->
        messages =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(fn line ->
            case Jason.decode(line) do
              {:ok, msg} -> [msg]
              _ -> []
            end
          end)

        {:ok, messages}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("MessageLog.load failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Load first N messages from a JSONL file efficiently (streaming).
  Returns {:ok, [message]} or {:ok, []} if file doesn't exist.
  """
  def load_up_to(path, count) when is_integer(count) and count > 0 do
    case File.open(path, [:read, :utf8]) do
      {:ok, file} ->
        try do
          messages =
            file
            |> IO.stream(:line)
            |> Stream.take(count)
            |> Enum.flat_map(fn line ->
              case Jason.decode(String.trim(line)) do
                {:ok, msg} -> [msg]
                _ -> []
              end
            end)

          {:ok, messages}
        after
          File.close(file)
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        Logger.warning("MessageLog.load_up_to failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def load_up_to(_path, count) when count <= 0, do: {:ok, []}

  # ── Private ──

  defp normalize(%AIBrain.Message{} = msg) do
    %{
      "role" => msg.role,
      "content" => msg.content,
      "ts" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp normalize(msg) when is_map(msg) do
    Map.put_new(msg, "ts", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  defp normalize({tag, data}) when is_atom(tag) do
    %{
      "error_type" => inspect(tag),
      "error_message" => inspect(data),
      "ts" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp normalize(other) do
    %{
      "raw_value" => inspect(other),
      "ts" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
