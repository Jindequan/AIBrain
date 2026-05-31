defmodule AIBrain.Telemetry.Sink do
  @moduledoc """
  Minimal pluggable telemetry sink.
  """

  def emit(nil, _event), do: :ok
  def emit(fun, event) when is_function(fun, 1), do: fun.(event)
  def emit(module, event) when is_atom(module), do: module.handle_event(event)
end
