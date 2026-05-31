defmodule AIBrain.Web.TasksHandlerTest do
  use AIBrain.DataCase, async: false
  import Plug.Test

  alias AIBrain.Web.Server

  test "GET /api/v1/tasks returns tasks list" do
    conn = conn(:get, "/api/v1/tasks") |> Server.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["tasks"])
  end
end
