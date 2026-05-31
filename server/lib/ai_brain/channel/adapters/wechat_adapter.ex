defmodule AIBrain.Channel.Adapters.WechatAdapter do
  @moduledoc """
  WeChat adapter bridge. Since personal WeChat has no official API,
  uses a webhook bridge (wechaty/itchat forwards messages here).

  Config: `webhook_secret` (shared secret for auth)
  """

  @behaviour AIBrain.Channel.Adapter

  def channel, do: :wechat

  @impl true
  def init(opts) do
    secret = Keyword.get(opts, :webhook_secret)

    if is_nil(secret) or secret == "",
      do: {:error, :missing_webhook_secret},
      else: {:ok, %{secret: secret}}
  end

  @impl true
  def send_message(state, message) do
    # message is a map with :to and :text keys from the dispatch queue
    to = message[:to] || message[:chat_id] || message["to"]
    text = message[:text] || message["text"] || ""
    {:ok, Map.put(state, :last_reply, %{to: to, text: text})}
  end

  @impl true
  def handle_inbound(state, payload) do
    with true <- valid_secret?(payload, state.secret),
         {:ok, msg} <- extract_message(payload) do
      result = %{
        channel: :wechat,
        sender_id: msg.from,
        sender_name: msg.from_name,
        text: msg.text,
        chat_type: msg.chat_type,
        chat_id: msg.chat_id,
        raw: payload
      }

      new_state =
        Map.merge(state, %{
          last_chat_type: msg.chat_type,
          last_chat_id: msg.chat_id
        })

      {:ok, [result], new_state}
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_secret?(payload, secret) do
    (payload["webhook_secret"] || payload["secret"]) == secret
  end

  defp extract_message(payload) do
    from = payload["from"] || payload["FromUserName"]
    text = payload["text"] || payload["Content"] || payload["message"]

    if is_nil(from) or from == "",
      do: {:error, :missing_sender},
      else:
        {:ok,
         %{
           from: from,
           from_name: payload["from_name"] || from,
           text: text || "",
           chat_type: payload["chat_type"] || "private",
           chat_id: payload["chat_id"] || from
         }}
  end
end
