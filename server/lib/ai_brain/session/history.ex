defmodule AIBrain.Session.History do
  @moduledoc """
  Session history management - clear data flow, NO mutation.

  ## Responsibilities

  - Load conversation history from storage
  - Merge history with new messages
  - Track turn count for resuming

  ## Data Flow

      Raw Input
        ↓
      LoadHistory.load(session_id, new_messages, opts)
        ↓
      %LoadResult{
        messages: history ++ new_messages,
        seed_turn: turn_count,
        source: :log | :memory | :none
      }
  """

  alias AIBrain.ConversationLog
  alias AIBrain.Session.HistoryMerge
  alias AIBrain.Session.Store.Memory

  defstruct [
    :messages,
    :seed_turn,
    :source
  ]

  @type t :: %__MODULE__{
          messages: list(map()),
          seed_turn: non_neg_integer(),
          source: :log | :memory | :none
        }

  @type source :: :log | :memory | :none

  @doc """
  Load session history and merge with new messages.

  Returns %History{messages, seed_turn, source}
  """
  def load(session_id, new_messages, opts \\ []) do
    cond = determine_load_condition(session_id, opts)

    case cond do
      :already_loaded ->
        build_already_loaded(new_messages)

      :from_log ->
        load_from_conversation_log(session_id, new_messages)

      :from_memory ->
        load_from_memory_store(session_id, new_messages, opts)

      :new_session ->
        build_new_session(new_messages)
    end
  end

  @doc """
  Prepend in-memory history if not already loaded from log.

  This is a SECONDARY history source (in-memory cache).
  """
  def prepend_memory_history(
        %__MODULE__{source: :log} = history,
        _session_store,
        _session_id,
        _opts
      ) do
    # Already loaded from log, don't prepend memory
    history
  end

  def prepend_memory_history(%__MODULE__{} = history, session_store, session_id, _opts) do
    memory_messages = Memory.resume_messages(session_store, session_id)

    if length(memory_messages) > 0 do
      %__MODULE__{
        history
        | messages: memory_messages ++ history.messages,
          source: :memory
      }
    else
      history
    end
  end

  # ── Private Loaders ─────────────────────────────────────────────

  defp determine_load_condition(_session_id, opts) do
    cond do
      Keyword.get(opts, :_history_loaded, false) ->
        :already_loaded

      Keyword.has_key?(opts, :session_id) ->
        :from_log

      Keyword.get(opts, :session_store) != nil ->
        :from_memory

      true ->
        :new_session
    end
  end

  defp build_already_loaded(messages) do
    %__MODULE__{
      messages: messages,
      seed_turn: count_assistant_turns(messages),
      # Assume from log if already loaded
      source: :log
    }
  end

  defp load_from_conversation_log(session_id, new_messages) do
    case ConversationLog.load_conversation(session_id) do
      {:ok, log_messages, _log} ->
        %__MODULE__{
          messages: HistoryMerge.merge(log_messages, new_messages),
          seed_turn: count_assistant_turns(log_messages),
          source: :log
        }

      {:error, _} ->
        build_new_session(new_messages)
    end
  end

  defp load_from_memory_store(session_id, new_messages, opts) do
    session_store = Keyword.get(opts, :session_store)

    if session_store do
      memory_messages = Memory.resume_messages(session_store, session_id)

      if length(memory_messages) > 0 do
        %__MODULE__{
          messages: memory_messages ++ new_messages,
          seed_turn: count_assistant_turns(memory_messages),
          source: :memory
        }
      else
        build_new_session(new_messages)
      end
    else
      build_new_session(new_messages)
    end
  end

  defp build_new_session(messages) do
    %__MODULE__{
      messages: messages,
      seed_turn: 0,
      source: :none
    }
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp count_assistant_turns(messages) do
    Enum.count(messages, fn message ->
      role(message) == "assistant"
    end)
  end

  defp role(%AIBrain.Message{role: role}), do: role
  defp role(%{role: role}), do: role
  defp role(%{"role" => role}), do: role
  defp role(_), do: nil
end
