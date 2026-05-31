defmodule AIBrain.AgentRuntime.GoalMetadata do
  @moduledoc """
  Standardized read/write interface for goal metadata fields.

  Reads from canonical flat keys first, falling back to the legacy nested keys.
  Writes to both canonical and legacy locations for backward compatibility.
  """

  @doc "Returns the current strategy assessment text."
  def current_strategy(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["current_strategy"] || get_in(meta, ["strategy", "current_assessment"]) || ""
  end

  @doc "Returns the next actions list."
  def next_actions(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["next_actions"] || get_in(meta, ["strategy", "next_actions"]) || []
  end

  @doc "Returns the blockers list."
  def blockers(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["blockers"] || get_in(meta, ["strategy", "blockers"]) || []
  end

  @doc "Returns the next review timestamp (ISO8601 string or nil)."
  def next_review_at(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["next_review_at"] || meta["next_review_after"]
  end

  @doc "Returns the last report text (ISO8601 timestamp of last review or nil)."
  def last_report(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["last_report"]
  end

  @doc "Returns whether the goal needs owner input."
  def needs_owner_input?(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    Map.get(meta, "needs_owner_input", false) == true or
      get_in(meta, ["strategy", "needs_owner_input"]) == true
  end

  @doc "Returns the last review started timestamp."
  def last_review_started_at(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["last_review_started_at"]
  end

  @doc "Returns the last review failed error."
  def last_review_error(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)
    meta["last_review_error"]
  end

  @doc "Returns all standardized fields as a map."
  def summary(goal_or_metadata) do
    meta = get_meta(goal_or_metadata)

    %{
      current_strategy: current_strategy(meta),
      next_actions: next_actions(meta),
      blockers: blockers(meta),
      next_review_at: next_review_at(meta),
      last_report: last_report(meta),
      needs_owner_input: needs_owner_input?(meta),
      last_review_started_at: last_review_started_at(meta),
      last_review_error: last_review_error(meta)
    }
  end

  @doc """
  Returns metadata with canonical keys added alongside existing keys.

  Designed to be called before `Goals.update` to ensure both old and new
  key paths are populated.
  """
  def enrich_metadata(metadata, strategy_updates \\ %{}) do
    meta = get_meta(metadata)

    meta =
      if strategy_updates != %{} do
        strategy = Map.get(meta, "strategy", %{})

        meta
        |> Map.put("current_strategy", Map.get(strategy_updates, "current_assessment", strategy["current_assessment"] || ""))
        |> Map.put("next_actions", Map.get(strategy_updates, "next_actions", strategy["next_actions"] || []))
        |> Map.put("blockers", Map.get(strategy_updates, "blockers", strategy["blockers"] || []))
        |> Map.put("needs_owner_input", Map.get(strategy_updates, "needs_owner_input", strategy["needs_owner_input"] || false))
      else
        meta
        |> maybe_copy("current_strategy", get_in(meta, ["strategy", "current_assessment"]))
        |> maybe_copy("next_actions", get_in(meta, ["strategy", "next_actions"]))
        |> maybe_copy("blockers", get_in(meta, ["strategy", "blockers"]))
        |> maybe_copy("needs_owner_input", get_in(meta, ["strategy", "needs_owner_input"]))
        |> maybe_copy("last_report", get_in(meta, ["strategy", "last_report"]))
      end

    meta
    |> maybe_copy("next_review_at", meta["next_review_after"])
  end

  defp get_meta(%{metadata: meta}) when is_map(meta), do: meta
  defp get_meta(%{metadata: _}), do: %{}
  defp get_meta(meta) when is_map(meta), do: meta
  defp get_meta(_), do: %{}

  defp maybe_copy(meta, _key, nil), do: meta
  defp maybe_copy(meta, _key, ""), do: meta
  defp maybe_copy(meta, _key, []), do: meta
  defp maybe_copy(meta, _key, false), do: meta
  defp maybe_copy(meta, key, value), do: Map.put_new(meta, key, value)
end
