defmodule AIBrain.Feedback.LessonExtractor do
  @moduledoc """
  Distills user feedback into actionable system lessons.

  Groups pending feedback by target_type, runs LLM to extract common
  patterns, and writes concise rules to the system_lessons table.
  """

  require Logger

  alias AIBrain.Data.{Feedbacks, SystemLessons}

  @doc "Process all unhandled feedback. Intended for periodic or event-driven calls."
  def run do
    AIBrain.Data.Feedbacks.list(status: "pending")
    |> Enum.group_by(& &1.target_type)
    |> Enum.each(fn {target_type, entries} ->
      try do
        extract_and_save(target_type, entries)
      rescue
        e -> Logger.warning("LessonExtractor: failed for #{target_type}: #{Exception.message(e)}")
      end
    end)
  end

  @doc "Extract lessons from a single feedback entry (synchronous, for immediate use)."
  def extract_one(target_type, entries) when is_list(entries) do
    with {:ok, lessons} <- distill(target_type, entries) do
      Enum.each(lessons, fn lesson_attrs ->
        case SystemLessons.create(lesson_attrs) do
          {:ok, lesson} ->
            Logger.info("LessonExtractor: created lesson #{lesson.id} for #{target_type}")

          {:error, _} ->
            :ok
        end
      end)

      # Mark all as applied
      Enum.each(entries, fn entry ->
        Feedbacks.update_status(entry.id, "applied")
      end)
    end
  end

  # ── Private ──

  defp extract_and_save(target_type, entries) do
    # Skip if too few entries to distill meaningfully
    if length(entries) < 1 do
      :ok
    else
      with {:ok, lessons} <- distill(target_type, entries) do
        Enum.each(lessons, fn lesson_attrs ->
          lesson_attrs =
            Map.merge(lesson_attrs, %{
              target_type: target_type,
              source_count: length(entries)
            })

          case SystemLessons.create(lesson_attrs) do
            {:ok, lesson} ->
              Logger.info("LessonExtractor: created lesson #{lesson.id} for #{target_type}")

            {:error, _} ->
              :ok
          end
        end)

        # Mark all processed feedback as applied
        Enum.each(entries, fn entry ->
          Feedbacks.update_status(entry.id, "applied")
        end)
      end
    end
  end

  defp distill(_target_type, entries) do
    # Simple keyword-based distillation — no LLM call for now.
    # Collects unique patterns from user corrections as plain-text rules.

    corrections =
      entries
      |> Enum.map(fn e ->
        "#{e.original_action} → #{e.user_correction || e.expected_action || "(flagged)"}"
      end)
      |> Enum.uniq()

    if corrections == [] do
      {:ok, []}
    else
      rule_text = Enum.map_join(corrections, "\n", &"- #{&1}")

      {:ok,
       [
         %{
           lesson: "User has corrected the following patterns:\n#{rule_text}",
           version: 1,
           active: true,
           changelog: "Auto-generated from #{length(entries)} feedback entries"
         }
       ]}
    end
  end
end
