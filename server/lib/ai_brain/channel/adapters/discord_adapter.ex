defmodule AIBrain.Channel.Adapters.DiscordAdapter do
  @moduledoc """
  Discord Bot API adapter for AIBrain gateway.

  Implements `AIBrain.Channel.Adapter` behaviour.

  - Handles inbound Discord interaction payloads (slash commands, message components, PING)
  - Sends AI responses via `POST /channels/{channel_id}/messages`
  - Uses Bot Token authentication (`Authorization: Bot <token>`)

  ## Config fields

    * `bot_token` — Discord bot token (required)
    * `application_id` — Discord application ID (required)
    * `allowed_guild_ids` — optional JSON array of allowed guild IDs
  """

  @behaviour AIBrain.Channel.Adapter

  @api_base "https://discord.com/api/v10"

  def channel, do: :discord

  @impl true
  def init(opts) do
    bot_token = Keyword.get(opts, :bot_token)
    application_id = Keyword.get(opts, :application_id)

    cond do
      is_nil(bot_token) ->
        {:error, :missing_bot_token}

      is_nil(application_id) ->
        {:error, :missing_application_id}

      true ->
        {:ok,
         %{
           bot_token: bot_token,
           application_id: application_id,
           channel_id: nil
         }}
    end
  end

  @impl true
  def handle_inbound(state, %{"type" => 1}) do
    # Discord PING interaction — acknowledge silently
    {:ok, [], state}
  end

  def handle_inbound(state, %{"content" => content} = payload) when is_binary(content) do
    # Direct message payload (DM or guild message_create)
    channel_id = payload_channel_id(state, payload)

    {:ok, [%{role: "user", content: content}],
     %{state | channel_id: channel_id || state.channel_id}}
  end

  def handle_inbound(state, %{"message" => %{"content" => content}} = payload) do
    # Message component interaction with embedded message content
    channel_id = payload_channel_id(state, payload)

    {:ok, [%{role: "user", content: content}],
     %{state | channel_id: channel_id || state.channel_id}}
  end

  def handle_inbound(state, %{"data" => %{"name" => cmd_name}} = payload) do
    # Slash command (interaction type 2)
    channel_id = payload_channel_id(state, payload)
    options = payload |> Map.get("data", %{}) |> Map.get("options", [])
    text = format_slash_command(cmd_name, options)
    {:ok, [%{role: "user", content: text}], %{state | channel_id: channel_id || state.channel_id}}
  end

  def handle_inbound(state, %{"data" => %{"content" => content}} = payload)
      when is_binary(content) do
    # Message data in nested data field
    channel_id = payload_channel_id(state, payload)

    {:ok, [%{role: "user", content: content}],
     %{state | channel_id: channel_id || state.channel_id}}
  end

  def handle_inbound(state, _payload) do
    # Unknown payload — nothing to process
    {:ok, [], state}
  end

  @impl true
  def send_message(state, %{type: :approval, approval_id: id, tool_name: tool_name, input: input}) do
    channel_id = state.channel_id

    if is_nil(channel_id) do
      {:error, :missing_channel_id}
    else
      input_preview =
        input
        |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
        |> Enum.join("\n")

      text = """
      ⚠️ **需要审批** [`#{id}`]
      操作：`#{tool_name}`
      参数：
      #{input_preview}
      """

      url = "#{@api_base}/channels/#{channel_id}/messages"

      case Req.post(
             url,
             Keyword.merge(
               [headers: auth_headers(state), json: %{content: text}],
               req_opts(state)
             )
           ) do
        {:ok, _} -> {:ok, state}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def send_message(state, %{content: content}) when is_binary(content) do
    channel_id = state.channel_id

    if is_nil(channel_id) do
      {:error, :missing_channel_id}
    else
      url = "#{@api_base}/channels/#{channel_id}/messages"

      case Req.post(
             url,
             Keyword.merge(
               [headers: auth_headers(state), json: %{content: content}],
               req_opts(state)
             )
           ) do
        {:ok, _response} -> {:ok, state}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def send_message(state, _message), do: {:ok, state}

  # ── Helpers ────────────────────────────────────────────────────

  defp auth_headers(state) do
    [
      {"Authorization", "Bot #{state.bot_token}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp payload_channel_id(_state, payload) do
    payload["channel_id"]
  end

  defp req_opts(state), do: Map.get(state, :req_opts, [])

  defp format_slash_command(name, options) do
    option_text =
      options
      |> Enum.map(fn opt ->
        "#{opt["name"]}: #{opt["value"]}"
      end)
      |> Enum.join(", ")

    if option_text == "" do
      "/#{name}"
    else
      "/#{name} #{option_text}"
    end
  end
end
