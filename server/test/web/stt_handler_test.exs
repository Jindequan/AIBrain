defmodule AIBrain.Web.STTHandlerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias AIBrain.Web.Handlers.STTHandler

  test "missing audio path does not leak local filesystem paths" do
    local_path = "/Users/example/private/audio.webm"

    conn =
      :post
      |> conn("/api/v1/stt/transcribe")
      |> STTHandler.handle_transcribe(%{"path" => local_path})

    body = Jason.decode!(conn.resp_body)
    assert conn.status == 400
    assert body["error"] == "Audio file not found"
    assert body["code"] == "audio_file_not_found"
    refute conn.resp_body =~ local_path
  end
end
