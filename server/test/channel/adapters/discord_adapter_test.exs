defmodule AIBrain.Channel.Adapters.DiscordAdapterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Adapters.DiscordAdapter

  describe "channel/0" do
    test "returns :discord" do
      assert DiscordAdapter.channel() == :discord
    end
  end

  describe "init/1" do
    test "requires bot_token" do
      assert {:error, :missing_bot_token} = DiscordAdapter.init(application_id: "app123")
    end

    test "requires application_id" do
      assert {:error, :missing_application_id} = DiscordAdapter.init(bot_token: "tok")
    end

    test "returns ok with state when both are present" do
      assert {:ok, %{bot_token: "tok", application_id: "app123", channel_id: nil}} =
               DiscordAdapter.init(bot_token: "tok", application_id: "app123")
    end
  end

  describe "handle_inbound/2" do
    setup do
      {:ok, state} = DiscordAdapter.init(bot_token: "tok", application_id: "app123")
      {:ok, state: state}
    end

    test "acknowledges PING interaction (type 1)", %{state: state} do
      assert {:ok, [], ^state} =
               DiscordAdapter.handle_inbound(state, %{"type" => 1, "id" => "ping"})
    end

    test "extracts text from direct message payload", %{state: state} do
      payload = %{
        "content" => "hello from discord",
        "channel_id" => "12345",
        "author" => %{"id" => "user1"}
      }

      assert {:ok, [%{role: "user", content: "hello from discord"}], new_state} =
               DiscordAdapter.handle_inbound(state, payload)

      assert new_state.channel_id == "12345"
    end

    test "extracts text from message in data field", %{state: state} do
      payload = %{
        "type" => 2,
        "data" => %{"content" => "hello via data"},
        "channel_id" => "67890",
        "member" => %{"user" => %{"id" => "user2"}}
      }

      assert {:ok, [%{role: "user", content: "hello via data"}], new_state} =
               DiscordAdapter.handle_inbound(state, payload)

      assert new_state.channel_id == "67890"
    end

    test "extracts text from message component with embedded message", %{state: state} do
      payload = %{
        "type" => 3,
        "message" => %{"content" => "component message text"},
        "channel_id" => "11111",
        "data" => %{"custom_id" => "btn_1"}
      }

      assert {:ok, [%{role: "user", content: "component message text"}], new_state} =
               DiscordAdapter.handle_inbound(state, payload)

      assert new_state.channel_id == "11111"
    end

    test "extracts slash command from interaction data", %{state: state} do
      payload = %{
        "type" => 2,
        "data" => %{"name" => "ask", "options" => [%{"name" => "query", "value" => "what is ai"}]},
        "channel_id" => "22222",
        "member" => %{"user" => %{"id" => "user3"}}
      }

      assert {:ok, [%{role: "user", content: "/ask query: what is ai"}], new_state} =
               DiscordAdapter.handle_inbound(state, payload)

      assert new_state.channel_id == "22222"
    end

    test "handles slash command without options", %{state: state} do
      payload = %{
        "type" => 2,
        "data" => %{"name" => "ping"},
        "channel_id" => "33333"
      }

      assert {:ok, [%{role: "user", content: "/ping"}], new_state} =
               DiscordAdapter.handle_inbound(state, payload)

      assert new_state.channel_id == "33333"
    end

    test "returns empty for unknown payload", %{state: state} do
      assert {:ok, [], ^state} = DiscordAdapter.handle_inbound(state, %{})
    end
  end

  describe "send_message/2" do
    setup do
      {:ok, state} = DiscordAdapter.init(bot_token: "bot_token_abc", application_id: "app123")

      state =
        Map.merge(state, %{channel_id: "98765", req_opts: [plug: {Req.Test, :discord_test}]})

      Req.Test.stub(:discord_test, fn conn ->
        send(self(), {:http_request, conn})
        Plug.Conn.send_resp(conn, 200, ~s<{"id": "123"}>)
      end)

      {:ok, state: state}
    end

    test "sends POST to correct Discord API URL with bot token auth, verifying HTTP call structure",
         %{state: state} do
      assert {:ok, _updated_state} = DiscordAdapter.send_message(state, %{content: "hello"})

      assert_received {:http_request, conn}
      assert conn.method == "POST"
      assert conn.request_path == "/api/v10/channels/98765/messages"
      assert conn.host == "discord.com"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bot bot_token_abc"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]

      body = IO.iodata_to_binary(Req.Test.raw_body(conn))
      assert body == Jason.encode!(%{content: "hello"})
    end

    test "approval message POSTs with correct channel URL and approval format" do
      {:ok, state} = DiscordAdapter.init(bot_token: "bt", application_id: "app")
      state = Map.merge(state, %{channel_id: "123", req_opts: [plug: {Req.Test, :discord_test}]})

      input = %{"query" => "what is ai"}
      msg = %{type: :approval, approval_id: "a1", tool_name: "search", input: input}

      assert {:ok, _state} = DiscordAdapter.send_message(state, msg)

      assert_received {:http_request, conn}
      assert conn.method == "POST"
      assert conn.request_path == "/api/v10/channels/123/messages"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bot bt"]

      body = IO.iodata_to_binary(Req.Test.raw_body(conn))
      decoded = Jason.decode!(body)
      assert decoded["content"] =~ "需要审批"
    end

    test "returns error when channel_id is nil" do
      {:ok, state} = DiscordAdapter.init(bot_token: "tok", application_id: "app123")
      assert {:error, :missing_channel_id} = DiscordAdapter.send_message(state, %{content: "hi"})
    end

    test "returns ok for unknown message format" do
      {:ok, state} = DiscordAdapter.init(bot_token: "tok", application_id: "app123")
      assert {:ok, ^state} = DiscordAdapter.send_message(state, %{unknown: "format"})
    end
  end
end
