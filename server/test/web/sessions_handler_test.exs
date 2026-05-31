defmodule AIBrain.Web.SessionsHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias AIBrain.Web.Server

  setup do
    case Process.whereis(AIBrain.Session.Store.Memory) do
      nil ->
        start_supervised!({AIBrain.Session.Store.Memory, [name: AIBrain.Session.Store.Memory]})

      _ ->
        :ok
    end

    %{}
  end

  test "GET /api/v1/sessions returns sessions list" do
    conn = conn(:get, "/api/v1/sessions") |> Server.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["sessions"])
  end

  test "POST /api/v1/sessions creates an empty chat session" do
    conn =
      :post
      |> conn("/api/v1/sessions", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert is_binary(body["session_id"])
    assert body["messages"] == []
  end

  test "POST /api/v1/sessions preserves workspace_path on empty session" do
    conn =
      :post
      |> conn("/api/v1/sessions", Jason.encode!(%{"workspace_path" => "/tmp/aibrain-chat"}))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 201
    body = Jason.decode!(conn.resp_body)
    assert body["workspace_path"] == "/tmp/aibrain-chat"
  end

  test "POST /api/v1/sessions/:id/stop is safe when session is not running" do
    conn =
      :post
      |> conn("/api/v1/sessions/not-running/stop", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "not_running"
    assert body["session_id"] == "not-running"
  end

  test "POST /api/v1/sessions/:id/stop aborts a registered running session" do
    session_id = "running-session-for-stop-test"
    pid = spawn(fn -> Process.sleep(:infinity) end)
    ref = Process.monitor(pid)
    :ok = AIBrain.Session.Registry.register(session_id, pid)

    conn =
      :post
      |> conn("/api/v1/sessions/#{session_id}/stop", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "stopped"
    assert body["session_id"] == session_id

    assert_receive {:DOWN, ^ref, :process, ^pid, :session_aborted}, 100
  end

  test "session registry try_register refuses to replace a live process" do
    session_id = "registry-running-#{System.unique_integer([:positive])}"
    first = spawn(fn -> Process.sleep(:infinity) end)
    second = spawn(fn -> Process.sleep(:infinity) end)

    try do
      assert :ok = AIBrain.Session.Registry.try_register(session_id, first)

      assert {:error, :already_running} =
               AIBrain.Session.Registry.try_register(session_id, second)

      assert {:ok, ^first} = AIBrain.Session.Registry.get_pid(session_id)
    after
      AIBrain.Session.Registry.unregister(session_id)
      Process.exit(first, :kill)
      Process.exit(second, :kill)
    end
  end
end
