defmodule AIBrain.ConversationLog do
  @moduledoc """
  对话日志：JSONL 格式，append-only。

  ## 存储布局

  ```
  ~/.aibrain/sessions/<session_id>/
  ├── conversation.jsonl          ← 消息明细（append-only，一行一条）
  ├── meta.json                   ← session 元数据（base_context, timestamps）
  └── tool-results/               ← 大于 5KB 的 tool result 外置存储
      ├── <tool_use_id>.txt
      └── <tool_use_id>.json
  ```

  ## 设计原则

  - 消息文件 conversation.jsonl 是唯一真相，append-only，崩溃安全
  - meta.json 存储 session 级元数据，体积小（< 1KB），低频更新
  - 大于 5KB 的 tool result 外置到 tool-results/ 目录
  """

  require Logger

  @log_file "conversation.jsonl"
  @meta_file "meta.json"
  @max_inline_size 5 * 1024

  # ── Public API ──

  @doc "追加单条消息（append-only，原子写入）"
  def append_message(session_id, message) do
    path = ensure_log_file(session_id)
    normalized = normalize_to_map(message)

    line = Jason.encode!(normalized) <> "\n"
    File.write!(path, append_prefix(path) <> line, [:append])

    :ok
  rescue
    e ->
      Logger.error("Failed to append message to #{session_id}: #{Exception.message(e)}")
      {:error, :append_failed}
  end

  @doc "追加多条消息。自动外置大 tool result。"
  def append_messages(session_id, new_messages, _opts \\ []) do
    path = ensure_log_file(session_id)

    normalized = Enum.map(new_messages, &normalize_to_map/1)

    lines =
      normalized
      |> externalize_batch(session_id)
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(path, append_prefix(path) <> lines <> "\n", [:append])

    :ok
  rescue
    e ->
      Logger.error("Failed to append messages to #{session_id}: #{Exception.message(e)}")
      {:error, :append_failed}
  end

  @doc """
  加载对话日志，返回消息数组。
  自动解析 output_ref 恢复完整内容。

  返回 {:ok, messages, meta} 其中 meta 是 meta.json 的内容（可能为空 map）。
  """
  def load_conversation(session_id) do
    path = log_file_path(session_id)

    if File.exists?(path) do
      messages =
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, msg} -> [msg]
            _ -> []
          end
        end)
        |> resolve_external_refs(session_id)
        |> Enum.map(&AIBrain.Message.from_json/1)
        |> Enum.to_list()

      meta = read_meta(session_id)
      {:ok, messages, meta}
    else
      {:error, :not_found}
    end
  rescue
    e ->
      Logger.error("Failed to load conversation for #{session_id}: #{Exception.message(e)}")
      {:error, :invalid_format}
  end

  @doc """
  分页加载消息。返回 {:ok, %{messages, total, has_more}}。

  - `limit` — 加载条数（默认 50）
  - `before` — 加载此索引之前的消息（从文件尾部倒数）

  只流式读取所需范围，不将整个文件加载到内存。
  """
  def load_paginated(session_id, opts \\ []) do
    path = log_file_path(session_id)
    limit = Keyword.get(opts, :limit, 50)
    before = Keyword.get(opts, :before)

    if File.exists?(path) do
      total = get_message_count(session_id, path)

      {start_idx, end_idx} =
        case before do
          nil ->
            start_idx = max(0, total - limit)
            {start_idx, total}

          idx when is_integer(idx) and idx >= 0 ->
            start_idx = max(0, idx - limit)
            {start_idx, idx}

          _ ->
            start_idx = max(0, total - limit)
            {start_idx, total}
        end

      has_more = start_idx > 0

      messages =
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.with_index()
        |> Stream.filter(fn {_, idx} -> idx >= start_idx and idx < end_idx end)
        |> Stream.map(fn {line, _} -> line end)
        |> Stream.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, msg} -> [msg]
            _ -> []
          end
        end)
        |> resolve_external_refs(session_id)
        |> Enum.map(&AIBrain.Message.from_json/1)

      {:ok, %{messages: messages, total: total, has_more: has_more}}
    else
      {:ok, %{messages: [], total: 0, has_more: false}}
    end
  rescue
    e ->
      Logger.error("Failed to load paginated for #{session_id}: #{Exception.message(e)}")
      {:error, :invalid_format}
  end

  @doc "Return the number of messages in the conversation log (0 if missing)."
  def message_count(session_id) do
    case summary(session_id) do
      {:ok, %{message_count: count}} when is_integer(count) -> count
      _ -> 0
    end
  end

  @doc "Read session-level metadata from meta.json (empty map if absent)."
  def session_meta(session_id), do: read_meta(session_id)

  @doc "获取对话摘要"
  def summary(session_id) do
    path = log_file_path(session_id)
    meta = read_meta(session_id)

    message_count =
      if File.exists?(path) do
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Enum.count()
      else
        0
      end

    {:ok,
     %{
       session_id: session_id,
       message_count: message_count,
       base_context: meta["base_context"],
       created_at: meta["created_at"],
       updated_at: meta["updated_at"]
     }}
  rescue
    _ -> {:error, :not_found}
  end

  @doc "设置 base_context（轮转时由 LLM 生成的历史摘要）"
  def set_base_context(session_id, summary) do
    meta = read_meta(session_id)

    updated =
      meta
      |> Map.put("base_context", summary)
      |> Map.put("updated_at", now_iso())

    write_meta(session_id, updated)
  end

  @doc "获取当前 base_context"
  def get_base_context(session_id) do
    meta = read_meta(session_id)

    case meta["base_context"] do
      ctx when is_binary(ctx) and ctx != "" -> {:ok, ctx}
      _ -> {:error, :not_found}
    end
  end

  @doc "替换整个消息列表（用于轮转、删除消息等低频操作）"
  def save_messages(session_id, messages, opts \\ []) do
    path = ensure_log_file(session_id)

    base_context = Keyword.get(opts, :base_context)

    normalized = Enum.map(messages, &normalize_to_map/1)

    lines =
      normalized
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(path, if(lines == "", do: "", else: lines <> "\n"))

    meta =
      read_meta(session_id)
      |> Map.put("message_count", length(normalized))

    meta =
      if base_context do
        Map.put(meta, "base_context", base_context)
      else
        meta
      end

    write_meta(session_id, meta)
    :ok
  rescue
    e ->
      Logger.error("Failed to save messages for #{session_id}: #{Exception.message(e)}")
      {:error, :save_failed}
  end

  @doc "Keep messages before the given 0-based index and discard the rest."
  def truncate_messages(session_id, from_index) when is_integer(from_index) and from_index >= 0 do
    with {:ok, messages, _meta} <- load_conversation(session_id) do
      kept = Enum.take(messages, from_index)
      save_messages(session_id, kept)
      {:ok, %{kept: length(kept), removed: max(length(messages) - length(kept), 0)}}
    end
  end

  @doc "清理 session 的外置 tool-result 文件"
  def cleanup_external_files(session_id) do
    dir = tool_results_dir(session_id)

    case File.rm_rf(dir) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  @doc false
  def tool_results_dir(session_id) do
    Path.join(session_dir_path(session_id), "tool-results")
  end

  @doc false
  def log_file_path(session_id) do
    Path.join(session_dir_path(session_id), @log_file)
  end

  @doc false
  def meta_file_path(session_id) do
    Path.join(session_dir_path(session_id), @meta_file)
  end

  # ── Meta JSON ──

  def read_meta(session_id) do
    path = meta_file_path(session_id)

    case File.read(path) do
      {:ok, content} ->
        try do
          Jason.decode!(content)
        rescue
          _ -> %{}
        end

      {:error, :enoent} ->
        %{}
    end
  end

  defp write_meta(session_id, meta) do
    path = meta_file_path(session_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(meta, pretty: true))
    :ok
  end

  @doc "Persist a single key-value pair to the session's meta.json."
  def put_session_meta(session_id, key, value) do
    meta = read_meta(session_id) |> Map.put(to_string(key), value)
    write_meta(session_id, meta)
  end

  defp get_message_count(_session_id, path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.count()
  end

  defp ensure_log_file(session_id) do
    path = log_file_path(session_id)
    File.mkdir_p!(Path.dirname(path))
    path
  end

  defp append_prefix(path) do
    case File.stat(path) do
      {:ok, %{size: 0}} ->
        ""

      {:ok, %{size: size}} ->
        case :file.open(String.to_charlist(path), [:read, :binary]) do
          {:ok, io} ->
            try do
              {:ok, <<last>>} = :file.pread(io, size - 1, 1)
              if last == ?\n, do: "", else: "\n"
            after
              :file.close(io)
            end

          _ ->
            ""
        end

      _ ->
        ""
    end
  end

  # ── Tool Result Externalization ──

  defp externalize_batch(messages, session_id) do
    Enum.map(messages, fn msg ->
      if is_list(msg["content"]) do
        updated_content =
          Enum.map(msg["content"], fn block ->
            if block["type"] == "tool_use" && should_externalize?(block["output"]) do
              ext = externalize_content(session_id, block["id"], block["output"])

              block
              |> Map.drop(["output"])
              |> Map.merge(ext)
            else
              block
            end
          end)

        Map.put(msg, "content", updated_content)
      else
        msg
      end
    end)
  end

  defp content_byte_size(nil), do: 0
  defp content_byte_size(content) when is_binary(content), do: byte_size(content)
  defp content_byte_size(content) when is_map(content), do: byte_size(Jason.encode!(content))
  defp content_byte_size(_), do: 0

  defp should_externalize?(content), do: content_byte_size(content) >= @max_inline_size

  defp externalize_content(session_id, tool_use_id, content) do
    dir = tool_results_dir(session_id)
    File.mkdir_p!(dir)

    ext = if is_binary(content), do: "txt", else: "json"
    filename = "#{tool_use_id}.#{ext}"
    file_path = Path.join(dir, filename)

    data = if is_binary(content), do: content, else: Jason.encode!(content)
    File.write!(file_path, data)

    %{
      "output_ref" => "tool-results/#{filename}",
      "output_size" => content_byte_size(content)
    }
  end

  defp resolve_external_refs(messages, session_id) do
    Enum.map(messages, fn msg ->
      if is_map(msg) && is_list(msg["content"]) do
        updated_content =
          Enum.map(msg["content"], fn block ->
            if block["type"] == "tool_use" && is_binary(block["output_ref"]) do
              session_dir = session_dir_path(session_id)
              file_path = Path.join([session_dir, block["output_ref"]])

              # Prevent path traversal: resolved path must stay within session directory.
              content =
                if safe_within_dir?(file_path, session_dir) do
                  case File.read(file_path) do
                    {:ok, data} ->
                      if String.ends_with?(block["output_ref"] || "", ".json") do
                        case Jason.decode(data) do
                          {:ok, decoded} -> decoded
                          {:error, _} -> "(corrupted: #{block["output_ref"]})"
                        end
                      else
                        data
                      end

                    {:error, reason} ->
                      Logger.warning(
                        "Failed to read externalized tool result #{file_path}: #{inspect(reason)}"
                      )

                      "(unavailable: #{block["output_ref"]})"
                  end
                else
                  Logger.warning("Blocked path traversal in output_ref: #{block["output_ref"]}")

                  "(blocked: #{block["output_ref"]})"
                end

              block
              |> Map.put("output", content)
              |> Map.drop(["output_ref", "output_size"])
            else
              block
            end
          end)

        Map.put(msg, "content", updated_content)
      else
        msg
      end
    end)
  end

  # ── Helpers ──

  defp normalize_to_map(%AIBrain.Message{} = msg) do
    %{
      "id" => msg.id,
      "role" => msg.role,
      "content" => msg.content,
      "name" => msg.name,
      "metadata" => msg.metadata,
      "created_at" => msg.created_at
    }
  end

  defp normalize_to_map(msg) when is_map(msg), do: msg

  defp session_dir_path(session_id) do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join([data_dir, "sessions", session_id])
  end

  defp now_iso do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp safe_within_dir?(file_path, parent_dir) do
    expanded = Path.expand(file_path)
    expanded_parent = Path.expand(parent_dir)
    expanded == expanded_parent or String.starts_with?(expanded, expanded_parent <> "/")
  rescue
    _ -> false
  end
end
