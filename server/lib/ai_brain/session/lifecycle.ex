defmodule AIBrain.Session.Lifecycle do
  @moduledoc """
  Session lifecycle management - clear data flow.

  ## Responsibilities

  - Start session (persist to store)
  - Session has no state machine - either alive (in DB) or deleted

  ## Before vs After

  ### BEFORE (stinking mess):
  ```elixir
  def start(session_store, session_id, messages, requested_model, opts) do
    channel_adapter = Keyword.get(opts, :channel_adapter)
    channel_id = Keyword.get(opts, :channel_id)
    session_type = Keyword.get(opts, :session_type, "manual")
    capabilities = Keyword.get(opts, :capability_summary, %{enabled: [], rejected: []})
    # ... scattered handling ...
  end
  ```

  ### AFTER (clean functional):
  ```elixir
  def start(session_store, session_id, messages, requested_model, opts) do
    config = StartConfig.build(session_id, messages, requested_model, opts)
    do_start(session_store, config)
  end
  ```
  """

  alias AIBrain.Session.Store.Memory
  alias AIBrain.Session.StartConfig

  @doc """
  Start a session - persist to store.

  If session_store is nil, no-op (for stateless sessions).
  """
  def start(nil, _session_id, _messages, _requested_model, _opts) do
    :ok
  end

  def start(session_store, session_id, messages, requested_model, opts) do
    config = StartConfig.build(session_id, messages, requested_model, opts)
    do_start(session_store, config)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp do_start(session_store, %StartConfig{} = config) do
    memory_format = StartConfig.to_memory_format(config)

    Memory.start_session(session_store, config.session_id, memory_format)
  end
end
