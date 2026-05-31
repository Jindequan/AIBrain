defmodule AIBrain.Channel.Config do
  @moduledoc """
  Channel configuration - explicit structure, NO guessing.

  Replaces scattered Keyword.get(opts, ...) calls.
  """

  defstruct [
    :consumer,
    :session_store,
    :session_id,
    :on_event,
    :mode,
    :audit_opts,
    :runtime_opts
  ]

  @type t :: %__MODULE__{
          consumer: pid() | nil,
          session_store: module() | nil,
          session_id: String.t() | nil,
          on_event: function(),
          mode: atom(),
          audit_opts: keyword(),
          runtime_opts: keyword()
        }

  @doc """
  Build channel config from options.

  ALL defaults resolved here. NO more Keyword.get downstream.
  """
  def build(opts) do
    on_event = build_on_event(opts)

    %__MODULE__{
      consumer: Keyword.get(opts, :consumer),
      session_store: Keyword.get(opts, :session_store),
      session_id: Keyword.get(opts, :session_id),
      on_event: on_event,
      mode: Keyword.get(opts, :mode, :auto),
      audit_opts: Keyword.get(opts, :audit_opts, []),
      runtime_opts: runtime_opts(opts)
    }
  end

  @doc """
  Convert to format expected by AgentRuntime.Orchestrator.
  """
  def to_runtime_opts(%__MODULE__{} = config) do
    [
      session_store: config.session_store,
      session_id: config.session_id,
      on_event: config.on_event,
      mode: config.mode
    ]
    |> Keyword.merge(config.runtime_opts || [])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp build_on_event(opts) do
    consumer = Keyword.get(opts, :consumer)
    caller_on_event = Keyword.get(opts, :on_event, fn _ -> :ok end)

    if consumer do
      forwarded = AIBrain.Channel.Consumer.event_handler(consumer)

      fn event ->
        caller_on_event.(event)
        forwarded.(event)
      end
    else
      caller_on_event
    end
  end

  defp runtime_opts(opts) do
    pass_through =
      [
        :router,
        :executor,
        :tools,
        :http_client,
        :model,
        :system,
        :workspace_path,
        :max_turns,
        :max_wall_time,
        :timeout,
        :approval_resolver,
        :telemetry_sink,
        :hooks,
        :context
      ]

    Keyword.take(opts, pass_through)
  end
end
