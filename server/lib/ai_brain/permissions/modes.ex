defmodule AIBrain.Permissions.Modes do
  @moduledoc """
  Normalizes runtime execution modes.

  Atom `nil` means "internal programmatic call — trust it" and maps to `:execute`.
  String values come from HTTP params and are converted to atoms.
  Unknown or unrecognized modes default to `:approval_required` (fail-safe).
  """

  @valid_modes [:execute, :plan, :approval_required]

  def valid_modes, do: @valid_modes

  # Internal programmatic calls (Planning.Agent, Executor, delegation) pass nil —
  # they run in a trusted context and should not require interactive approval.
  def normalize(nil), do: :execute
  def normalize(mode) when mode in @valid_modes, do: mode
  # String modes come from HTTP params
  def normalize("execute"), do: :execute
  def normalize("plan"), do: :plan
  def normalize("approval_required"), do: :approval_required
  # Unknown or :default → require approval (fail-safe)
  def normalize(_mode), do: :approval_required
end
