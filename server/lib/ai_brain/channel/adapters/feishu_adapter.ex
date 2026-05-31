defmodule AIBrain.Channel.Adapters.FeishuAdapter do
  @moduledoc """
  Feishu (Lark) Open API adapter for AIBrain gateway.

  Implements `AIBrain.Channel.Adapter` behaviour.

  - Handles inbound Feishu event callback payloads (text messages, interactive cards)
  - Supports URL verification challenge (echoes back challenge token)
  - Sends AI responses via Feishu Message API with tenant_access_token auth

  ## Config fields

    * `app_id` — Feishu app ID (required)
    * `app_secret` — Feishu app secret (required)
  """

  @behaviour AIBrain.Channel.Adapter

  @api_base "https://open.feishu.cn/open-apis"

  def channel, do: :feishu

  @impl true
  def init(opts) do
    app_id = Keyword.get(opts, :app_id)
    app_secret = Keyword.get(opts, :app_secret)
    chat_id = Keyword.get(opts, :chat_id)

    cond do
      is_nil(app_id) ->
        {:error, :missing_app_id}

      is_nil(app_secret) ->
        {:error, :missing_app_secret}

      true ->
        {:ok,
         %{
           app_id: app_id,
           app_secret: app_secret,
           chat_id: chat_id
         }}
    end
  end

  @impl true
  def handle_inbound(state, %{"type" => "url_verification", "challenge" => challenge}) do
    # URL verification challenge — the webhook handler returns the challenge,
    # but if it reaches the adapter, respond with it here too
    {:ok, [%{role: "system", content: "url_verification:#{challenge}"}], state}
  end

  def handle_inbound(state, %{"type" => "event_callback", "event" => event}) do
    extract_event(state, event)
  end

  def handle_inbound(state, _payload) do
    {:ok, [], state}
  end

  @impl true
  def send_message(state, %{type: :approval, approval_id: id, tool_name: tool_name, input: input}) do
    chat_id = state.chat_id

    if is_nil(chat_id) do
      {:error, :missing_chat_id}
    else
      input_preview =
        input
        |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
        |> Enum.join("\n")

      text = """
      ⚠️ Approval needed [`#{id}`]
      Action: `#{tool_name}`
      Params:
      #{input_preview}
      """

      send_feishu_message(state, chat_id, text)
    end
  end

  def send_message(state, %{content: content}) when is_binary(content) do
    chat_id = state.chat_id

    if is_nil(chat_id) do
      {:error, :missing_chat_id}
    else
      send_feishu_message(state, chat_id, content)
    end
  end

  def send_message(state, %{type: :interaction} = msg) do
    chat_id = state.chat_id

    if is_nil(chat_id) do
      {:error, :missing_chat_id}
    else
      text = build_interaction_text(msg)
      send_feishu_message(state, chat_id, text)
    end
  end

  def send_message(state, _message), do: {:ok, state}

  # ── Interaction Helpers ──

  defp build_interaction_text(%{
         interaction_type: "confirm",
         interaction_id: id,
         schema: schema,
         reason: reason
       }) do
    """
    ⚠️ 需要你的决定 [#{String.slice(id, 0, 8)}]

    #{schema[:title] || "确认"}
    #{schema[:prompt] || ""}
    #{if reason && reason != "", do: "\n原因: #{reason}"}

    请通过 API 或 Web 页面处理此请求：
    批准 → POST /api/v1/interactions/#{id}/resolve  {decision: "approved"}
    拒绝 → POST /api/v1/interactions/#{id}/resolve  {decision: "denied"}
    """
  end

  defp build_interaction_text(%{
         interaction_type: "select",
         interaction_id: id,
         schema: schema,
         reason: reason
       }) do
    options =
      schema[:fields]
      |> List.wrap()
      |> Enum.find(%{}, fn f -> is_map(f) && f[:key] == :choice end)
      |> Map.get(:options, [])

    options_text =
      options
      |> Enum.with_index(1)
      |> Enum.map(fn {opt, i} -> "  #{i}. #{opt}" end)
      |> Enum.join("\n")

    """
    ⚠️ 请选择 [#{String.slice(id, 0, 8)}]

    #{schema[:title] || "选择"}
    #{schema[:prompt] || ""}
    #{if reason && reason != "", do: "\n原因: #{reason}"}

    选项:
    #{options_text}

    请通过 API 处理：POST /api/v1/interactions/#{id}/resolve  {selected_index: <数字>}
    """
  end

  defp build_interaction_text(%{
         interaction_type: "text_input",
         interaction_id: id,
         schema: schema,
         reason: reason
       }) do
    """
    ✍️ 需要你提供信息 [#{String.slice(id, 0, 8)}]

    #{schema[:title] || "信息"}
    #{schema[:prompt] || ""}
    #{if reason && reason != "", do: "\n原因: #{reason}"}

    请通过 API 处理：POST /api/v1/interactions/#{id}/resolve  {text: "你的回答"}
    """
  end

  defp build_interaction_text(%{
         interaction_type: "form",
         interaction_id: id,
         schema: schema,
         reason: reason
       }) do
    fields = List.wrap(schema[:fields])

    fields_text =
      fields
      |> Enum.with_index(1)
      |> Enum.map(fn {f, i} ->
        label = f[:label] || f[:key] || "Field #{i}"
        type = f[:type] || "text"
        required = if f[:required], do: " (必填)", else: " (可选)"
        "  #{i}. [#{type}] #{label}#{required}"
      end)
      |> Enum.join("\n")

    """
    📋 需要填写表单 [#{String.slice(id, 0, 8)}]

    #{schema[:title] || "表单"}
    #{schema[:prompt] || ""}
    #{if reason && reason != "", do: "\n原因: #{reason}"}

    字段:
    #{fields_text}

    请通过 API 处理：POST /api/v1/interactions/#{id}/resolve  {form: {"field_key": "value", ...}}
    """
  end

  defp build_interaction_text(%{interaction_id: id}) do
    "⚠️ Interaction #{String.slice(id || "", 0, 8)} requires your attention."
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp extract_event(state, %{"type" => "im.message.receive_v1", "message" => message}) do
    extract_message(state, message)
  end

  defp extract_event(state, _event), do: {:ok, [], state}

  defp extract_message(state, %{
         "message_type" => "text",
         "content" => content,
         "chat_id" => chat_id
       }) do
    case Jason.decode(content) do
      {:ok, %{"text" => text}} ->
        {:ok, [%{role: "user", content: text}], %{state | chat_id: chat_id}}

      _ ->
        {:ok, [], state}
    end
  end

  defp extract_message(state, %{"chat_id" => chat_id}) do
    # Non-text message type — acknowledge but don't process
    {:ok, [], %{state | chat_id: chat_id}}
  end

  defp extract_message(state, _message), do: {:ok, [], state}

  defp send_feishu_message(state, chat_id, text) do
    with {:ok, token} <- get_tenant_access_token(state) do
      url = "#{@api_base}/im/v1/messages"

      body =
        Jason.encode!(%{
          receive_id: chat_id,
          msg_type: "text",
          content: Jason.encode!(%{text: text})
        })

      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(url, Keyword.merge([headers: headers, body: body], req_opts(state))) do
        {:ok, _response} -> {:ok, state}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_tenant_access_token(state) do
    url = "#{@api_base}/auth/v3/tenant_access_token/internal"

    body =
      Jason.encode!(%{
        app_id: state.app_id,
        app_secret: state.app_secret
      })

    headers = [{"Content-Type", "application/json"}]

    case Req.post(url, Keyword.merge([headers: headers, body: body], req_opts(state))) do
      {:ok, %Req.Response{body: body}} ->
        parse_token_response(body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_token_response(%{"tenant_access_token" => token}), do: {:ok, token}

  defp parse_token_response(%{"code" => code, "msg" => msg}) when code != 0,
    do: {:error, "Feishu auth error: #{msg}"}

  defp parse_token_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_token_response(decoded)
      {:error, _} -> {:error, "Feishu auth unexpected response: #{inspect(body)}"}
    end
  end

  defp parse_token_response(body),
    do: {:error, "Feishu auth unexpected response: #{inspect(body)}"}

  defp req_opts(state), do: Map.get(state, :req_opts, [])
end
