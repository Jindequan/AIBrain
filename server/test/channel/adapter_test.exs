defmodule AIBrain.Channel.AdapterTest do
  use ExUnit.Case, async: true

  defmodule StubAdapter do
    @behaviour AIBrain.Channel.Adapter

    @impl true
    def init(opts), do: {:ok, %{greeting: Keyword.get(opts, :greeting, "hi")}}

    @impl true
    def handle_inbound(state, %{"text" => text}) do
      {:ok, [%{role: "user", content: text}], state}
    end

    def handle_inbound(state, _), do: {:ok, [], state}

    @impl true
    def send_message(state, %{content: content}) do
      send(self(), {:sent, content})
      {:ok, state}
    end
  end

  describe "Adapter behaviour" do
    test "init/1 returns ok with state" do
      assert {:ok, %{greeting: "hi"}} = StubAdapter.init([])
      assert {:ok, %{greeting: "hello"}} = StubAdapter.init(greeting: "hello")
    end

    test "handle_inbound/2 extracts messages" do
      {:ok, state} = StubAdapter.init([])

      assert {:ok, [%{role: "user", content: "hello"}], ^state} =
               StubAdapter.handle_inbound(state, %{"text" => "hello"})
    end

    test "handle_inbound/2 returns empty for non-text" do
      {:ok, state} = StubAdapter.init([])
      assert {:ok, [], ^state} = StubAdapter.handle_inbound(state, %{"photo" => %{}})
    end

    test "send_message/2 delivers message" do
      {:ok, state} = StubAdapter.init([])
      assert {:ok, ^state} = StubAdapter.send_message(state, %{content: "reply"})
      assert_received {:sent, "reply"}
    end
  end
end
