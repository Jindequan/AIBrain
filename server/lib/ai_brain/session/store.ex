defmodule AIBrain.Session.Store do
  @moduledoc """
  Behaviour for durable session history storage.

  基于 conversation.jsonl 的文件系统存储。

  ## 存储格式

  所有会话数据存储在 {data_dir}/sessions/{session_id}/conversation.jsonl
  """

  @callback start_link(keyword()) :: GenServer.on_start()
  @callback start_session(GenServer.server(), String.t(), keyword()) :: :ok
  @callback append_event(GenServer.server(), String.t(), map()) :: :ok
  @callback append_message(GenServer.server(), String.t(), map()) :: :ok
  @callback delete_message(GenServer.server(), String.t(), String.t()) ::
              :ok | {:error, :not_found}
  @callback truncate_messages(GenServer.server(), String.t(), non_neg_integer()) ::
              {:ok, map()} | {:error, :not_found | term()}
  @callback load_session(GenServer.server(), String.t()) ::
              {:ok, map()} | {:error, :not_found | term()}
  @callback load_session_head(GenServer.server(), String.t()) ::
              {:ok, map()} | {:error, :not_found | term()}
  @callback delete_session(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  @callback list_sessions(GenServer.server()) :: list(map())
  @callback resume_messages(GenServer.server(), String.t()) :: list()
  @callback flush_to_disk(GenServer.server(), String.t()) :: :ok | {:error, term()}
  @callback update_workspace_path(GenServer.server(), String.t(), String.t() | nil) :: :ok
  @callback maybe_rotate(GenServer.server(), String.t()) :: {:continue, String.t()}
  @callback find_session_by_isolation(
              GenServer.server(),
              String.t() | nil,
              String.t() | nil,
              String.t() | nil
            ) ::
              {:ok, String.t()} | {:error, :not_found}

  @optional_callbacks [maybe_rotate: 2]

  @doc """
  查找或创建 session，按隔离条件去重。

  当提供了 workspace_path 或 channel_adapter+channel_id 时，
  优先查找已存在的 session，避免为同一上下文创建多个 session。
  """
  def find_or_create_session!(store, opts) do
    workspace_path = Keyword.get(opts, :workspace_path)
    channel_adapter = Keyword.get(opts, :channel_adapter)
    channel_id = Keyword.get(opts, :channel_id)

    cond do
      # Channel session: always deduplicate by channel_adapter+channel_id,
      # regardless of workspace_path. workspace_path is metadata, not a dedup key.
      channel_adapter && channel_id ->
        case store.find_session_by_isolation(store, nil, channel_adapter, channel_id) do
          {:ok, existing_id} ->
            {existing_id, :existing}

          _ ->
            session_id = generate_session_id()
            :ok = store.start_session(store, session_id, opts)
            {session_id, :created}
        end

      # Web session: deduplicate by workspace_path
      workspace_path ->
        case store.find_session_by_isolation(store, workspace_path, nil, nil) do
          {:ok, existing_id} ->
            {existing_id, :existing}

          _ ->
            session_id = generate_session_id()
            :ok = store.start_session(store, session_id, opts)
            {session_id, :created}
        end

      # No isolation: always create new
      true ->
        session_id = generate_session_id()
        :ok = store.start_session(store, session_id, opts)
        {session_id, :created}
    end
  end

  defp generate_session_id do
    "session-" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  # ── Shared Helpers ───────────────────────────────────────────

  @doc false
  def derive_title([]), do: "New Session"

  def derive_title(messages) do
    case Enum.find(messages, &user_message?/1) do
      nil -> "New Session"
      msg -> extract_first_text(msg) |> format_title()
    end
  end

  defp user_message?(%{role: "user"}), do: true
  defp user_message?(%{"role" => "user"}), do: true
  defp user_message?(_), do: false

  defp extract_first_text(%{content: [%{type: "text", text: text} | _]}) when is_binary(text),
    do: text

  defp extract_first_text(%{"content" => [%{"type" => "text", "text" => text} | _]})
       when is_binary(text), do: text

  defp extract_first_text(%{content: content}) when is_binary(content), do: content
  defp extract_first_text(%{"content" => content}) when is_binary(content), do: content
  defp extract_first_text(_), do: nil

  defp format_title(nil), do: "New Session"

  defp format_title(text) do
    trimmed = text |> String.replace("\n", " ") |> String.slice(0, 60) |> String.trim()
    if byte_size(text) > 60, do: trimmed <> "...", else: trimmed
  end

  @doc false
  def derive_title_for_update(current_title, messages) do
    cond do
      is_nil(current_title) or current_title == "New Session" -> derive_title(messages)
      true -> current_title
    end
  end

  defmodule Memory do
    @moduledoc """
    内存中的 session store 实现，用于测试。
    """

    use GenServer

    @behaviour AIBrain.Session.Store

    def start_link(opts \\ []) do
      case Keyword.get(opts, :name, __MODULE__) do
        nil -> GenServer.start_link(__MODULE__, %{})
        name -> GenServer.start_link(__MODULE__, %{}, name: name)
      end
    end

    def start_session(server \\ __MODULE__, session_id, opts \\ []) do
      GenServer.call(server, {:start_session, session_id, opts})
    end

    def append_event(server \\ __MODULE__, session_id, event) do
      GenServer.call(server, {:append_event, session_id, event})
    end

    def append_message(server \\ __MODULE__, session_id, message) do
      GenServer.call(server, {:append_message, session_id, message})
    end

    def load_session(server \\ __MODULE__, session_id) do
      GenServer.call(server, {:load_session, session_id})
    end

    def load_session_head(server \\ __MODULE__, session_id) do
      GenServer.call(server, {:load_session_head, session_id})
    end

    def delete_session(server \\ __MODULE__, session_id) do
      GenServer.call(server, {:delete_session, session_id})
    end

    def update_title(server \\ __MODULE__, session_id, title) do
      GenServer.call(server, {:update_title, session_id, title})
    end

    def update_workspace_path(server \\ __MODULE__, session_id, path) do
      GenServer.call(server, {:update_workspace_path, session_id, path})
    end

    def delete_message(server \\ __MODULE__, session_id, message_id) do
      GenServer.call(server, {:delete_message, session_id, message_id})
    end

    def truncate_messages(server \\ __MODULE__, session_id, from_index) do
      GenServer.call(server, {:truncate_messages, session_id, from_index})
    end

    def list_sessions(server \\ __MODULE__) do
      GenServer.call(server, :list_sessions)
    end

    def resume_messages(server \\ __MODULE__, session_id) do
      case load_session(server, session_id) do
        {:error, :not_found} -> []
        {:ok, session} -> session.messages
      end
    end

    def find_session_by_isolation(
          server \\ __MODULE__,
          workspace_path,
          channel_adapter,
          channel_id
        ) do
      GenServer.call(
        server,
        {:find_session_by_isolation, workspace_path, channel_adapter, channel_id}
      )
    end

    def flush_to_disk(_server \\ __MODULE__, _session_id) do
      :ok
    end

    def maybe_rotate(_server \\ __MODULE__, session_id) do
      {:continue, session_id}
    end

    def init(state), do: {:ok, %{sessions: state}}

    def handle_call({:start_session, session_id, opts}, _from, %{sessions: sessions} = state) do
      metadata = Keyword.get(opts, :metadata, %{})
      new_messages = Keyword.get(opts, :messages, [])
      requested_model = Keyword.get(opts, :requested_model)
      workspace_path = Keyword.get(opts, :workspace_path)

      updated =
        case Map.get(sessions, session_id) do
          nil ->
            %{
              session_id: session_id,
              title:
                Keyword.get(opts, :title) || AIBrain.Session.Store.derive_title(new_messages),
              workspace_path: workspace_path,
              metadata: metadata |> Map.put(:requested_model, requested_model),
              messages: new_messages,
              events: [],
              runtime_events: [],
              created_at: DateTime.utc_now() |> DateTime.to_iso8601()
            }

          existing ->
            merged_metadata =
              existing.metadata
              |> Map.merge(metadata)
              |> Map.put(:requested_model, requested_model || existing.metadata[:requested_model])

            %{
              existing
              | metadata: merged_metadata,
                workspace_path: workspace_path || existing.workspace_path
            }
        end

      {:reply, :ok, put_in(state, [:sessions, session_id], updated)}
    end

    def handle_call({:append_event, session_id, event}, _from, state) do
      {:reply, :ok,
       update_session(state, session_id, fn session ->
         %{session | runtime_events: (session.runtime_events || []) ++ [event]}
       end)}
    end

    def handle_call({:append_message, session_id, message}, _from, state) do
      {:reply, :ok,
       update_session(state, session_id, fn session ->
         new_messages = session.messages ++ [message]

         %{
           session
           | messages: new_messages,
             title: AIBrain.Session.Store.derive_title_for_update(session.title, new_messages)
         }
       end)}
    end

    def handle_call({:update_title, session_id, title}, _from, state) do
      {:reply, :ok,
       update_session(state, session_id, fn session ->
         %{session | title: title}
       end)}
    end

    def handle_call({:update_workspace_path, session_id, path}, _from, state) do
      {:reply, :ok,
       update_session(state, session_id, fn session ->
         %{session | workspace_path: path}
       end)}
    end

    def handle_call({:load_session, session_id}, _from, %{sessions: sessions} = state) do
      case Map.get(sessions, session_id) do
        nil ->
          case AIBrain.ConversationLog.load_conversation(session_id) do
            {:ok, messages, meta} ->
              session = %{
                session_id: session_id,
                title: AIBrain.Session.Store.derive_title(messages),
                base_context: meta["base_context"],
                workspace_path: meta["workspace_path"],
                messages: messages,
                events: [],
                runtime_events: [],
                metadata: %{requested_model: meta["requested_model"]},
                created_at: meta["created_at"]
              }

              {:reply, {:ok, session}, put_in(state, [:sessions, session_id], session)}

            {:error, :not_found} ->
              {:reply, {:error, :not_found}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end

        session ->
          {:reply, {:ok, session}, state}
      end
    end

    def handle_call({:load_session_head, session_id}, _from, %{sessions: sessions} = state) do
      case Map.get(sessions, session_id) do
        %{} = session ->
          head =
            session
            |> Map.put(:messages, [])
            |> Map.put(:message_count, length(session.messages || []))

          {:reply, {:ok, head}, state}

        nil ->
          case AIBrain.ConversationLog.summary(session_id) do
            {:ok, summary} ->
              meta = AIBrain.ConversationLog.session_meta(session_id)

              head = %{
                session_id: session_id,
                title: meta["title"] || "New Session",
                workspace_path: meta["workspace_path"],
                metadata: %{requested_model: meta["requested_model"]},
                messages: [],
                message_count: summary.message_count,
                runtime_events: [],
                created_at: meta["created_at"],
                updated_at: meta["updated_at"] || meta["created_at"]
              }

              {:reply, {:ok, head}, state}

            {:error, :not_found} ->
              {:reply, {:error, :not_found}, state}
          end
      end
    end

    def handle_call(:list_sessions, _from, %{sessions: sessions} = state) do
      summaries =
        Enum.map(sessions, fn {session_id, session} ->
          %{
            session_id: session_id,
            title: Map.get(session, :title, "New Session"),
            workspace_path: Map.get(session, :workspace_path),
            requested_model: session.metadata[:requested_model],
            message_count: length(session.messages),
            created_at: Map.get(session, :created_at),
            updated_at: Map.get(session, :created_at)
          }
        end)

      {:reply, summaries, state}
    end

    def handle_call(
          {:find_session_by_isolation, workspace_path, channel_adapter, channel_id},
          _from,
          %{sessions: sessions} = state
        ) do
      result =
        Enum.find_value(sessions, fn
          {id, %{workspace_path: ^workspace_path}} when is_binary(workspace_path) ->
            {:ok, id}

          {id, %{metadata: %{channel_adapter: ca, channel_id: ci}}}
          when is_binary(channel_adapter) and is_binary(channel_id) and ca == channel_adapter and
                 ci == channel_id ->
            {:ok, id}

          _ ->
            nil
        end)

      {:reply, result || {:error, :not_found}, state}
    end

    def handle_call({:delete_session, session_id}, _from, %{sessions: sessions} = state) do
      if Map.has_key?(sessions, session_id) do
        {:reply, :ok, put_in(state, [:sessions], Map.delete(sessions, session_id))}
      else
        {:reply, {:error, :not_found}, state}
      end
    end

    def handle_call(
          {:delete_message, session_id, message_id},
          _from,
          %{sessions: sessions} = state
        ) do
      case Map.get(sessions, session_id) do
        nil ->
          {:reply, {:error, :not_found}, state}

        session ->
          new_messages =
            Enum.reject(session.messages, fn m ->
              Map.get(m, :id) == message_id || Map.get(m, "id") == message_id
            end)

          if length(new_messages) == length(session.messages) do
            {:reply, {:error, :not_found}, state}
          else
            updated = %{session | messages: new_messages}
            {:reply, :ok, put_in(state, [:sessions, session_id], updated)}
          end
      end
    end

    def handle_call(
          {:truncate_messages, session_id, from_index},
          _from,
          %{sessions: sessions} = state
        ) do
      case Map.get(sessions, session_id) do
        nil ->
          {:reply, {:error, :not_found}, state}

        session ->
          kept = Enum.take(session.messages, from_index)
          updated = %{session | messages: kept}

          {:reply, {:ok, %{kept: length(kept), removed: length(session.messages) - length(kept)}},
           put_in(state, [:sessions, session_id], updated)}
      end
    end

    def handle_call({:flush_to_disk, _session_id}, _from, state) do
      {:reply, :ok, state}
    end

    defp update_session(%{sessions: sessions} = state, session_id, fun) do
      session =
        Map.get(sessions, session_id, %{
          session_id: session_id,
          metadata: %{},
          messages: [],
          events: []
        })

      put_in(state, [:sessions, session_id], fun.(session))
    end
  end
end
