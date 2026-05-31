defmodule AIBrain.Web.Handlers.PlanningHandler do
  @moduledoc """
  HTTP handler for the planning endpoint.

  Accepts a user request and delegates to AIBrain.Planning.Agent.
  """

  import Plug.Conn
  require Logger
  alias AIBrain.Planning.Planner

  def handle_plan(conn, params) do
    user_request = params["user_request"] || params["prompt"]

    if is_nil(user_request) || user_request == "" do
      json(conn, 422, %{error: "user_request is required"})
    else
      case Planner.plan(user_request) do
        {:ok, plan} ->
          json(conn, 201, plan)

        {:error, reason} ->
          Logger.error("Planning failed: #{inspect(reason)}")
          json(conn, 422, %{error: "Failed to create plan"})
      end
    end
  end

  def handle_replan(conn, goal_id, params) do
    feedback = params["feedback"] || params["user_request"]

    if is_nil(feedback) || feedback == "" do
      json(conn, 422, %{error: "feedback is required"})
    else
      case Planner.replan(goal_id, feedback) do
        {:ok, plan} ->
          json(conn, 200, plan)

        {:error, reason} ->
          Logger.error("Replanning failed for goal #{goal_id}: #{inspect(reason)}")
          json(conn, 422, %{error: "Failed to replan"})
      end
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
