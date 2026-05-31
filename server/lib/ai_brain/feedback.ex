defmodule AIBrain.Feedback do
  @moduledoc """
  Facade for the feedback system.

  Provides a single entry point for creating feedback entries and
  retrieving lessons for prompt injection.
  """

  alias AIBrain.Data.Feedbacks
  alias AIBrain.Data.SystemLessons

  @doc """
  Submit user feedback on a system decision.

  Returns `{:ok, feedback}` or `{:error, reason}`.
  """
  def submit(attrs) when is_map(attrs) do
    case Feedbacks.create(attrs) do
      {:ok, feedback} ->
        # Broadcast event so downstream listeners (notifications, etc.) can react
        try do
          AIBrain.Channel.Bus.publish(%{
            type: :feedback_submitted,
            feedback_id: feedback.id,
            target_type: feedback.target_type,
            severity: feedback.severity
          })
        rescue
          _ -> :ok
        end

        # If significant severity, trigger immediate lesson extraction
        if feedback.severity in ~w(significant critical) do
          Task.start(fn ->
            AIBrain.Feedback.LessonExtractor.extract_one(feedback.target_type, [feedback])
          end)
        end

        {:ok, feedback}

      {:error, changeset} ->
        {:error, inspect(changeset.errors)}
    end
  end

  @doc """
  Get relevant lesson snippets for prompt injection into a decision context.
  """
  def lessons_for_prompt(target_type) do
    SystemLessons.format_for_prompt(target_type)
  end

  @doc """
  Get active lessons for a target type, as a list of maps.
  """
  def active_lessons(target_type) do
    SystemLessons.active_for(target_type)
  end

  @doc """
  List feedback entries with optional filters.
  """
  def list(opts \\ []) do
    Feedbacks.list(opts)
  end

  @doc """
  Run the lesson extractor on all pending feedback.
  """
  def distill_pending! do
    AIBrain.Feedback.LessonExtractor.run()
  end
end
