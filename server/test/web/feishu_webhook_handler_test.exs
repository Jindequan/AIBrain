defmodule AIBrain.Web.Handlers.FeishuWebhookHandlerTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias AIBrain.Web.Handlers.FeishuWebhookHandler

  describe "handle_webhook/2 — URL verification" do
    test "POST with url_verification returns the challenge" do
      conn =
        conn(:post, "/api/v1/channels/feishu/webhook", %{
          "type" => "url_verification",
          "challenge" => "test123"
        })

      conn =
        FeishuWebhookHandler.handle_webhook(conn, %{
          "type" => "url_verification",
          "challenge" => "test123"
        })

      assert conn.status == 200
      assert conn.resp_body == Jason.encode!(%{challenge: "test123"})
    end

    test "returns challenge with complex token" do
      conn =
        conn(:post, "/api/v1/channels/feishu/webhook", %{
          "type" => "url_verification",
          "challenge" => "abc123xyz789"
        })

      conn =
        FeishuWebhookHandler.handle_webhook(conn, %{
          "type" => "url_verification",
          "challenge" => "abc123xyz789"
        })

      assert conn.status == 200
      assert conn.resp_body == Jason.encode!(%{challenge: "abc123xyz789"})
    end
  end

  describe "handle_webhook/2 — dispatch" do
    test "returns 503 when no adapter worker is registered" do
      conn =
        conn(:post, "/api/v1/channels/feishu/webhook", %{
          "type" => "event_callback",
          "event" => %{
            "type" => "im.message.receive_v1",
            "message" => %{
              "chat_id" => "oc_xxx",
              "message_type" => "text",
              "content" => ~s({"text":"hello"})
            }
          }
        })

      conn =
        FeishuWebhookHandler.handle_webhook(conn, %{
          "type" => "event_callback",
          "event" => %{
            "type" => "im.message.receive_v1",
            "message" => %{
              "chat_id" => "oc_xxx",
              "message_type" => "text",
              "content" => ~s({"text":"hello"})
            }
          }
        })

      assert conn.status == 503
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Gateway not configured"
    end
  end
end
