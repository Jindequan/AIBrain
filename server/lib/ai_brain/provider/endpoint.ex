defmodule AIBrain.Provider.Endpoint do
  @enforce_keys [:protocol, :base_url, :api_key]
  defstruct [:protocol, :base_url, :api_key, retry_at: 0.0]

  @type t :: %__MODULE__{
          protocol: String.t(),
          base_url: String.t(),
          api_key: String.t(),
          retry_at: float()
        }

  def available?(%__MODULE__{retry_at: retry_at}) do
    now_seconds() >= retry_at
  end

  def set_cooldown(%__MODULE__{retry_at: existing} = ep, until) do
    %{ep | retry_at: max(existing, until)}
  end

  def soonest_recovery(%__MODULE__{retry_at: retry_at}), do: retry_at

  defp now_seconds, do: System.os_time(:millisecond) / 1000
end
