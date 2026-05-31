defmodule AIBrain.Web.PlanningHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AIBrain.Web.Handlers.PlanningHandler

  describe "handle_plan/2" do
    test "returns 422 when user_request is missing" do
      conn = conn(:post, "/api/v1/planning/plan")
      conn = PlanningHandler.handle_plan(conn, %{})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "user_request is required"
    end

    test "returns 422 when user_request is empty" do
      conn = conn(:post, "/api/v1/planning/plan")
      conn = PlanningHandler.handle_plan(conn, %{"user_request" => ""})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "user_request is required"
    end

    test "returns 422 when prompt is empty" do
      conn = conn(:post, "/api/v1/planning/plan")
      conn = PlanningHandler.handle_plan(conn, %{"prompt" => ""})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "user_request is required"
    end
  end
end
