defmodule AIBrain.Channel.Adapters.WhatsappAdapter do
  @moduledoc """
  WhatsApp adapter bridge. Uses whatsapp-web.js bridge.

  Config: `webhook_secret` (shared secret for auth)
  """

  @behaviour AIBrain.Channel.Adapter

  def channel, do: :whatsapp

  @impl true
  def init(opts) do
    secret = Keyword.get(opts, :webhook_secret)

    if is_nil(secret) or secret == "",
      do: {:error, :missing_webhook_secret},
      else: {:ok, %{secret: secret}}
  end

  @impl true
  def send_message(state, message) do
    to = message[:to] || message["to"]
    text = message[:text] || message["text"] || ""

    safe_text =
      if byte_size(text) > 4096,
        do: String.slice(text, 0, 4076) <> "... (truncated)",
        else: text

    {:ok, Map.put(state, :last_reply, %{to: to, text: safe_text})}
  end

  @impl true
  def handle_inbound(state, payload) do
    with true <- valid_secret?(payload, state.secret),
         {:ok, msg} <- extract_message(payload) do
      result = %{
        channel: :whatsapp,
        sender_id: msg.from,
        sender_name: msg.from_name,
        text: msg.text,
        chat_type: msg.chat_type,
        has_media: msg.has_media,
        raw: payload
      }

      {:ok, [result], Map.put(state, :last_from, msg.from)}
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_secret?(payload, secret) do
    (payload["webhook_secret"] || payload["secret"] || payload["verify_token"]) == secret
  end

  defp extract_message(payload) do
    from = payload["from"] || payload["From"]
    text = payload["text"] || payload["body"] || payload["Body"]

    if is_nil(from) or from == "",
      do: {:error, :missing_sender},
      else:
        {:ok,
         %{
           from: from,
           from_name: payload["from_name"] || from,
           text: text || "",
           chat_type: payload["chat_type"] || "private",
           has_media: payload["has_media"] || false
         }}
  end
end
