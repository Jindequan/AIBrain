defmodule AIBrain.Channel.Adapters.FeishuAdapterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Adapters.FeishuAdapter

  describe "channel/0" do
    test "returns :feishu" do
      assert FeishuAdapter.channel() == :feishu
    end
  end

  describe "init/1" do
    test "requires app_id" do
      assert {:error, :missing_app_id} = FeishuAdapter.init(app_secret: "secret123")
    end

    test "requires app_secret" do
      assert {:error, :missing_app_secret} = FeishuAdapter.init(app_id: "cli_xxx")
    end

    test "returns ok with state when both are present" do
      assert {:ok, %{app_id: "cli_xxx", app_secret: "secret123", chat_id: nil}} =
               FeishuAdapter.init(app_id: "cli_xxx", app_secret: "secret123")
    end
  end

  describe "handle_inbound/2" do
    setup do
      {:ok, state} = FeishuAdapter.init(app_id: "cli_xxx", app_secret: "secret123")
      {:ok, state: state}
    end

    test "extracts text from Feishu message event payload", %{state: state} do
      payload = %{
        "type" => "event_callback",
        "event" => %{
          "type" => "im.message.receive_v1",
          "message" => %{
            "chat_id" => "oc_abc123",
            "chat_type" => "p2p",
            "message_type" => "text",
            "content" => ~s({"text":"hello from feishu"}),
            "message_id" => "om_xyz"
          }
        }
      }

      assert {:ok, [%{role: "user", content: "hello from feishu"}], new_state} =
               FeishuAdapter.handle_inbound(state, payload)

      assert new_state.chat_id == "oc_abc123"
    end

    test "extracts text from p2p message without chat_id at top level", %{state: state} do
      payload = %{
        "type" => "event_callback",
        "event" => %{
          "type" => "im.message.receive_v1",
          "message" => %{
            "chat_id" => "oc_xyz789",
            "chat_type" => "p2p",
            "message_type" => "text",
            "content" => ~s({"text":"hello"}),
            "message_id" => "om_789"
          }
        }
      }

      assert {:ok, [%{role: "user", content: "hello"}], new_state} =
               FeishuAdapter.handle_inbound(state, payload)

      assert new_state.chat_id == "oc_xyz789"
    end

    test "handles interactive card messages by skipping silently", %{state: state} do
      payload = %{
        "type" => "event_callback",
        "event" => %{
          "type" => "im.message.receive_v1",
          "message" => %{
            "chat_id" => "oc_card_chat",
            "chat_type" => "p2p",
            "message_type" => "interactive",
            "content" => ~s({"config":{"wide_screen_mode":true}}),
            "message_id" => "om_card"
          }
        }
      }

      assert {:ok, [], new_state} = FeishuAdapter.handle_inbound(state, payload)
      assert new_state.chat_id == "oc_card_chat"
    end

    test "ignores non-message events", %{state: state} do
      payload = %{
        "type" => "event_callback",
        "event" => %{
          "type" => "app.open",
          "app_id" => "cli_xxx"
        }
      }

      assert {:ok, [], ^state} = FeishuAdapter.handle_inbound(state, payload)
    end

    test "returns empty for unknown payload", %{state: state} do
      assert {:ok, [], ^state} = FeishuAdapter.handle_inbound(state, %{})
    end
  end

  describe "send_message/2" do
    setup do
      {:ok, state} = FeishuAdapter.init(app_id: "cli_test", app_secret: "sec_test")

      state =
        Map.merge(state, %{chat_id: "oc_chat_123", req_opts: [plug: {Req.Test, :feishu_test}]})

      {:ok, state: state}
    end

    test "obtains tenant_access_token then POSTs to Feishu message API, verifying HTTP call structure",
         %{state: state} do
      # Stub the auth token endpoint first
      Req.Test.stub(:feishu_test, fn conn ->
        if String.ends_with?(conn.request_path, "/tenant_access_token/internal") do
          send(self(), {:auth_request, conn})

          Plug.Conn.send_resp(
            conn,
            200,
            ~s({"code":0,"tenant_access_token":"fake_token_abc","expire":7200})
          )
        else
          send(self(), {:message_request, conn})
          Plug.Conn.send_resp(conn, 200, ~s({"code":0,"message_id":"om_sent_123"}))
        end
      end)

      assert {:ok, _updated_state} =
               FeishuAdapter.send_message(state, %{content: "hello from ai"})

      # Verify auth request
      assert_received {:auth_request, auth_conn}
      assert auth_conn.method == "POST"
      assert auth_conn.request_path == "/open-apis/auth/v3/tenant_access_token/internal"
      assert auth_conn.host == "open.feishu.cn"
      assert Plug.Conn.get_req_header(auth_conn, "content-type") == ["application/json"]

      auth_body = IO.iodata_to_binary(Req.Test.raw_body(auth_conn))
      assert auth_body == Jason.encode!(%{app_id: "cli_test", app_secret: "sec_test"})

      # Verify message request
      assert_received {:message_request, msg_conn}
      assert msg_conn.method == "POST"
      assert msg_conn.request_path == "/open-apis/im/v1/messages"
      assert msg_conn.host == "open.feishu.cn"
      assert Plug.Conn.get_req_header(msg_conn, "authorization") == ["Bearer fake_token_abc"]
      assert Plug.Conn.get_req_header(msg_conn, "content-type") == ["application/json"]

      msg_body = IO.iodata_to_binary(Req.Test.raw_body(msg_conn))
      decoded = Jason.decode!(msg_body)
      assert decoded["receive_id"] == "oc_chat_123"
      assert decoded["msg_type"] == "text"
      content_decoded = Jason.decode!(decoded["content"])
      assert content_decoded["text"] == "hello from ai"
    end

    test "approval message format sends correctly" do
      {:ok, state} = FeishuAdapter.init(app_id: "cli_test", app_secret: "sec_test")

      state =
        Map.merge(state, %{chat_id: "oc_approval", req_opts: [plug: {Req.Test, :feishu_test}]})

      Req.Test.stub(:feishu_test, fn conn ->
        if String.ends_with?(conn.request_path, "/tenant_access_token/internal") do
          Plug.Conn.send_resp(conn, 200, ~s({"code":0,"tenant_access_token":"tok","expire":7200}))
        else
          send(self(), {:approval_request, conn})
          Plug.Conn.send_resp(conn, 200, ~s({"code":0}))
        end
      end)

      msg = %{
        type: :approval,
        approval_id: "a1",
        tool_name: "web_search",
        input: %{"q" => "hello"}
      }

      assert {:ok, _state} = FeishuAdapter.send_message(state, msg)

      assert_received {:approval_request, conn}
      body = IO.iodata_to_binary(Req.Test.raw_body(conn))
      decoded = Jason.decode!(body)
      assert decoded["receive_id"] == "oc_approval"
      assert decoded["msg_type"] == "text"
      content_decoded = Jason.decode!(decoded["content"])
      assert content_decoded["text"] =~ "Approval needed"
    end

    test "returns error when chat_id is nil" do
      {:ok, state} = FeishuAdapter.init(app_id: "cli_test", app_secret: "sec_test")
      assert {:error, :missing_chat_id} = FeishuAdapter.send_message(state, %{content: "hi"})
    end

    test "returns ok for unknown message format" do
      {:ok, state} = FeishuAdapter.init(app_id: "cli_test", app_secret: "sec_test")
      assert {:ok, ^state} = FeishuAdapter.send_message(state, %{unknown: "format"})
    end
  end
end
