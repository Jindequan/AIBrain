defmodule AIBrain.Channel.Responders.OperatorResponder do
  @moduledoc """
  Builds channel-friendly assistant replies for operator diagnostics.
  """

  alias AIBrain.Channel.Reply
  alias AIBrain.Permissions.Explainer

  def build_capability_rejection(rejection) when is_map(rejection) do
    explanation = Explainer.explain_capability_rejection(rejection)
    {:ok, build_reply(:capability_rejection, explanation)}
  end

  def build_permission_denial(event) when is_map(event) do
    explanation = Explainer.explain_permission_denial(event)
    {:ok, build_reply(:permission_denial, explanation)}
  end

  def build_permission_event(%{type: :permission_checked, decision: decision} = event)
      when decision in [:denied, "denied"] do
    build_permission_denial(event)
  end

  def build_permission_event(_event), do: {:error, :unsupported_event}

  def build_sandbox_feedback(event) when is_map(event) do
    explanation = Explainer.explain_sandbox_feedback(event)
    {:ok, build_reply(:sandbox_feedback, explanation)}
  end

  defp build_reply(diagnostic_type, explanation) do
    Reply.build(:operator_diagnostic, render_text(explanation), %{
      diagnostic_type: diagnostic_type
    })
  end

  defp render_text(explanation) do
    [
      explanation.title,
      explanation.summary,
      explanation.detail,
      "Next step: #{explanation.next_step}"
    ]
    |> Enum.join("\n")
  end
end
