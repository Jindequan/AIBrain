defmodule AIBrain.Web.FeishuConfigCRUDTest do
  use AIBrain.DataCase, async: false
  import Plug.Test

  alias AIBrain.Web.Server

  describe "POST /api/v1/channels/configs with channel_type=feishu" do
    test "creates a channel configuration" do
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "feishu",
          "name" => "My Feishu Bot",
          "app_id" => "cli_xxxxx",
          "app_secret" => "sec_xxxxx",
          "verification_token" => "verify_xxx",
          "enabled" => true
        })
        |> Server.call([])

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert is_binary(body["id"])
    end

    test "rejects creation without channel_type" do
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "name" => "Bad Config"
        })
        |> Server.call([])

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Validation failed"
    end

    test "rejects creation with invalid channel_type" do
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "slack",
          "name" => "Bad Config"
        })
        |> Server.call([])

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Validation failed"
    end

    test "accepts bridge channel types used by webhook routes" do
      for channel_type <- ["wechat", "whatsapp"] do
        conn =
          conn(:post, "/api/v1/channels/configs", %{
            "channel_type" => channel_type,
            "name" => "#{channel_type} bridge",
            "enabled" => false
          })
          |> Server.call([])

        assert conn.status == 201
        assert Jason.decode!(conn.resp_body)["ok"] == true
      end
    end
  end

  describe "GET /api/v1/channels/configs with channel_type=feishu" do
    test "lists configurations by channel_type" do
      # First create one
      _conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "feishu",
          "name" => "List Test",
          "app_id" => "cli_list",
          "app_secret" => "sec_list",
          "enabled" => true
        })
        |> Server.call([])

      # Then list
      conn =
        conn(:get, "/api/v1/channels/configs", %{"channel_type" => "feishu"})
        |> Server.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_list(body["configs"])
      assert length(body["configs"]) >= 1
    end
  end

  describe "GET /api/v1/channels/configs/:id with channel_type=feishu" do
    test "gets a specific configuration" do
      # Create first
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "feishu",
          "name" => "Get Test",
          "app_id" => "cli_get",
          "app_secret" => "sec_get",
          "enabled" => true
        })
        |> Server.call([])

      created = Jason.decode!(conn.resp_body)

      # Get it
      conn =
        conn(:get, "/api/v1/channels/configs/#{created["id"]}", %{"channel_type" => "feishu"})
        |> Server.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["id"] == created["id"]
      assert body["name"] == "Get Test"
      assert body["channel_type"] == "feishu"
    end

    test "returns 404 for non-existent configuration" do
      conn =
        conn(:get, "/api/v1/channels/configs/nonexistent", %{})
        |> Server.call([])

      assert conn.status == 404
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Configuration not found"
    end
  end

  describe "PUT /api/v1/channels/configs/:id with channel_type=feishu" do
    test "updates a configuration" do
      # Create first
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "feishu",
          "name" => "Update Test",
          "app_id" => "cli_update",
          "app_secret" => "sec_update",
          "enabled" => false
        })
        |> Server.call([])

      created = Jason.decode!(conn.resp_body)

      # Update it
      conn =
        conn(:put, "/api/v1/channels/configs/#{created["id"]}", %{
          "channel_type" => "feishu",
          "name" => "Updated Name",
          "app_id" => "cli_update",
          "app_secret" => "sec_updated",
          "enabled" => true
        })
        |> Server.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
      assert body["id"] == created["id"]
    end
  end

  describe "DELETE /api/v1/channels/configs/:id with channel_type=feishu" do
    test "deletes a configuration" do
      # Create first
      conn =
        conn(:post, "/api/v1/channels/configs", %{
          "channel_type" => "feishu",
          "name" => "Delete Test",
          "app_id" => "cli_delete",
          "app_secret" => "sec_delete",
          "enabled" => false
        })
        |> Server.call([])

      created = Jason.decode!(conn.resp_body)

      # Delete it
      conn =
        conn(:delete, "/api/v1/channels/configs/#{created["id"]}", %{"channel_type" => "feishu"})
        |> Server.call([])

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["ok"] == true
    end
  end
end
