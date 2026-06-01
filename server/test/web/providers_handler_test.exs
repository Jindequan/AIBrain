defmodule AIBrain.Web.ProvidersHandlerTest do
  use AIBrain.DataCase
  import Plug.Test
  import Plug.Conn

  alias AIBrain.Provider.Router
  alias AIBrain.Web.Handlers.ProvidersHandler
  alias AIBrain.Web.Server

  test "GET /api/v1/providers returns providers list" do
    conn = conn(:get, "/api/v1/providers") |> Server.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["providers"])
  end

  test "GET /api/v1/scheduler returns scheduler items" do
    conn = conn(:get, "/api/v1/scheduler") |> Server.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["items"])
  end

  test "provider list never exposes saved API keys" do
    name = unique_provider_name("secret")

    create_provider!(%{
      "name" => name,
      "api_key" => "sk-test-secret",
      "base_url" => "https://api.example.com/v1",
      "enabled" => true,
      "manual_models" => %{"private-model" => %{"types" => ["text"]}},
      "enabled_models" => ["private-model"]
    })

    conn = conn(:get, "/api/v1/providers") |> Server.call([])
    body = Jason.decode!(conn.resp_body)
    provider = Enum.find(body["providers"], &(&1["name"] == name))

    assert provider["configured"] == true
    assert provider["has_api_key"] == true
    assert provider["api_key"] == nil
  end

  test "provider config serialization never exposes saved API keys" do
    name = unique_provider_name("config-secret")

    create_provider!(%{
      "name" => name,
      "api_key" => "sk-config-secret",
      "base_url" => "https://api.example.com/v1",
      "enabled" => true
    })

    conn = conn(:get, "/api/v1/my-models")
    conn = ProvidersHandler.handle_my_models(conn)
    body = Jason.decode!(conn.resp_body)
    provider = Enum.find(body["providers"], &(&1["id"] == name))

    assert provider["has_key"] == true
    refute conn.resp_body =~ "sk-config-secret"
  end

  test "renaming a provider properly updates the new name" do
    old_name = unique_provider_name("old")
    new_name = unique_provider_name("new")

    create_provider!(%{
      "name" => old_name,
      "api_key" => "sk-test",
      "base_url" => "https://api.example.com/v1",
      "enabled" => true
    })

    conn =
      :put
      |> conn("/api/v1/providers/#{old_name}", Jason.encode!(%{"name" => new_name}))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 200

    # Verify new name appears in provider list with key configured
    list_conn = conn(:get, "/api/v1/providers") |> Server.call([])
    body = Jason.decode!(list_conn.resp_body)
    new_provider = Enum.find(body["providers"], &(&1["name"] == new_name))
    assert new_provider, "New provider name should appear in list"
    assert new_provider["configured"] == true
  end

  test "router can select enabled manual models" do
    provider = %AIBrain.Provider.Info{
      name: unique_provider_name("manual"),
      api_key: "sk-test",
      base_url: "https://api.example.com/v1",
      priority: 1,
      enabled: true,
      models: %{"private-chat" => %{"enabled" => true, "types" => ["text"]}}
    }

    {:ok, router} = Router.start_link(providers: [provider], name: nil)

    assert {:ok, selected_provider, "private-chat"} =
             Router.select(router, model: "private-chat")

    assert selected_provider.name == provider.name
  end

  defp create_provider!(body) do
    conn =
      :post
      |> conn("/api/v1/providers", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> Server.call([])

    assert conn.status == 201
    Jason.decode!(conn.resp_body)
  end

  defp unique_provider_name(prefix) do
    "#{prefix}-provider-#{System.unique_integer([:positive])}"
  end
end
