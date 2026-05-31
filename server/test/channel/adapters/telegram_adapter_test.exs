defmodule AIBrain.Channel.Adapters.TelegramAdapterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Adapters.TelegramAdapter

  describe "init/1" do
    test "requires bot_token and chat_id" do
      assert {:error, :missing_bot_token} = TelegramAdapter.init(chat_id: "123")
      assert {:error, :missing_chat_id} = TelegramAdapter.init(bot_token: "tok")
      assert {:ok, _} = TelegramAdapter.init(bot_token: "tok", chat_id: "123")
    end
  end

  describe "handle_inbound/2" do
    setup do
      {:ok, state} = TelegramAdapter.init(bot_token: "tok", chat_id: "123")
      {:ok, state: state}
    end

    test "extracts text message", %{state: state} do
      update = %{"message" => %{"text" => "hello assistant"}}

      assert {:ok, [%{role: "user", content: "hello assistant"}], ^state} =
               TelegramAdapter.handle_inbound(state, update)
    end

    test "extracts caption from media", %{state: state} do
      update = %{"message" => %{"caption" => "photo description"}}

      assert {:ok, [%{role: "user", content: "photo description"}], ^state} =
               TelegramAdapter.handle_inbound(state, update)
    end

    test "returns empty for non-text updates", %{state: state} do
      update = %{"message" => %{"photo" => [%{"file_id" => "abc"}]}}
      assert {:ok, [], ^state} = TelegramAdapter.handle_inbound(state, update)
    end

    test "returns empty for unknown payload", %{state: state} do
      assert {:ok, [], ^state} = TelegramAdapter.handle_inbound(state, %{})
    end
  end

  describe "channel/0" do
    test "returns :telegram" do
      assert TelegramAdapter.channel() == :telegram
    end
  end
end
