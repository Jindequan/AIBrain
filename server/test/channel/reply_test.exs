defmodule AIBrain.Channel.ReplyTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Reply

  test "build/3 returns a normalized channel reply envelope" do
    reply = Reply.build(:capability_status, "Capability Status", %{session_id: "s1"})

    assert %{
             role: "assistant",
             content: "Capability Status",
             metadata: %{
               kind: :channel_reply,
               schema_version: 1,
               surface: :capability_status,
               session_id: "s1"
             }
           } = reply
  end
end
