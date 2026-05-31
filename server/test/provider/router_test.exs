defmodule AIBrain.Provider.RouterTest do
  use ExUnit.Case, async: false
  alias AIBrain.Provider.{Info, Router}

  defp provider(name, priority) do
    %Info{
      name: name,
      api_key: "key-#{name}",
      base_url: "http://#{String.downcase(name)}",
      chat_url: "http://#{String.downcase(name)}/chat",
      priority: priority,
      enabled: true,
      models: %{"default" => %{"enabled" => true}}
    }
  end

  setup do
    providers = [provider("P1", 1), provider("P2", 2)]
    {:ok, pid} = Router.start_link(providers: providers, name: nil)

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, router: pid}
  end

  test "select returns highest priority available provider", %{router: r} do
    assert {:ok, p, "default"} = Router.select(r, type: :llm)
    assert p.name == "P1"
  end

  test "after P1 cooldown, select returns P2", %{router: r} do
    future = System.os_time(:millisecond) / 1000 + 3600
    Router.set_cooldown(r, "P1", "openai", future)
    assert {:ok, p, "default"} = Router.select(r, type: :llm)
    assert p.name == "P2"
  end

  test "returns error with soonest_recovery when all unavailable", %{router: r} do
    future = System.os_time(:millisecond) / 1000 + 3600
    Router.set_cooldown(r, "P1", "openai", future)
    Router.set_cooldown(r, "P2", "openai", future + 100)
    assert {:error, {:all_unavailable, soonest}} = Router.select(r, type: :llm)
    assert_in_delta soonest, future, 1.0
  end

  test "cooldown is lifted after retry_at passes", %{router: r} do
    past = System.os_time(:millisecond) / 1000 - 1
    Router.set_cooldown(r, "P1", "openai", past)
    assert {:ok, p, "default"} = Router.select(r, type: :llm)
    assert p.name == "P1"
  end

  test "non openai-compatible presets without chat_url expose no chat endpoint" do
    provider = %Info{
      name: "google",
      api_key: "key-google",
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      chat_url: nil,
      priority: 1,
      enabled: true
    }

    assert Info.chat_endpoint(provider) == nil
    assert Info.get_endpoint(provider, "openai") == nil
  end
end
