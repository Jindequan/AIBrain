defmodule AIBrain.Web.DashboardHandlerTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias AIBrain.Web.Handlers.DashboardHandler

  test "returns HTML with 200 status" do
    conn =
      :get
      |> conn("/dashboard")
      |> DashboardHandler.handle_dashboard()

    assert conn.status == 200
    assert String.contains?(conn.resp_body, "<!DOCTYPE html>")
    assert String.contains?(conn.resp_body, "AIBrain Dashboard")
  end
end
