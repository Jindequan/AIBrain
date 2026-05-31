defmodule AIBrain.Channel.Alert do
  @moduledoc """
  Structured alert with severity, dedup, and cooldown support.

  Used by Bus to prevent alert storms — identical alerts within the cooldown window
  are suppressed.
  """

  @type severity :: :critical | :warning | :info
  @type t :: %__MODULE__{
          severity: severity(),
          source: atom() | String.t(),
          type: String.t(),
          message: String.t(),
          dedup_key: String.t(),
          cooldown_ms: non_neg_integer(),
          metadata: map()
        }

  defstruct [
    :severity,
    :source,
    :type,
    :message,
    :dedup_key,
    :metadata,
    cooldown_ms: 300_000
  ]

  @default_cooldowns %{
    critical: 60_000,
    warning: 300_000,
    info: 900_000
  }

  @doc """
  Create a new alert. Computes dedup_key from source + type if not given.
  Uses default cooldowns per severity if not specified.
  """
  def new(severity, source, type, message, opts \\ []) do
    dedup_key = Keyword.get(opts, :dedup_key, "#{source}:#{type}")
    cooldown = Keyword.get(opts, :cooldown_ms, Map.get(@default_cooldowns, severity, 300_000))

    %__MODULE__{
      severity: severity,
      source: source,
      type: type,
      message: message,
      dedup_key: dedup_key,
      cooldown_ms: cooldown,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Check if this alert should be suppressed based on recent alert history.
  Returns true if an alert with the same dedup_key was fired within cooldown_ms.
  """
  def suppressed?(%__MODULE__{} = alert, recent_alerts) do
    cutoff = System.system_time(:millisecond) - alert.cooldown_ms

    Enum.any?(recent_alerts, fn {key, fired_at} ->
      key == alert.dedup_key and fired_at > cutoff
    end)
  end
end
