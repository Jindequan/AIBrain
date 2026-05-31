defmodule AIBrain.Web.FsHandlerTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias AIBrain.Web.Server

  test "file read rejects raw path traversal before expansion normalizes it away" do
    conn =
      conn(:get, "/api/v1/file/read?path=#{URI.encode_www_form("../secret.txt")}")
      |> Server.call([])

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["error"] =~ "Path traversal"
  end

  test "directory list rejects raw path traversal before fallback handling" do
    conn =
      conn(:get, "/api/v1/fs?path=#{URI.encode_www_form("../")}")
      |> Server.call([])

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["error"] =~ "Path traversal"
  end
end
