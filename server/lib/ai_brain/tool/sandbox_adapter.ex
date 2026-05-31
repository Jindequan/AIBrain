defmodule AIBrain.Tool.SandboxAdapter do
  @moduledoc """
  Normalizes sandbox-blocked tool execution results into surfaced feedback.
  """

  alias AIBrain.Core.Events
  alias AIBrain.Tool.Error

  def feedback_event(tool_use_id, {:error, {:sandbox_blocked, operation, detail}}) do
    Events.sandbox_feedback(tool_use_id, operation, :blocked, %{detail: detail})
  end

  def feedback_event(tool_use_id, {:error, %Error{category: :permission, message: msg}}) do
    Events.sandbox_feedback(tool_use_id, "permission", :blocked, %{detail: msg})
  end

  def feedback_event(_tool_use_id, _result), do: nil

  def tool_result_content({:error, {:sandbox_blocked, _operation, detail}}), do: detail
  def tool_result_content({:error, %Error{message: msg}}), do: msg
  def tool_result_content({_status, content}), do: content
  def tool_result_content(content), do: content
end
