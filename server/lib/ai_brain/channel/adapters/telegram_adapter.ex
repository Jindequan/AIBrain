defmodule AIBrain.Channel.Adapters.TelegramAdapter do
  @moduledoc """
  Telegram Bot API adapter for AIBrain gateway.
  """

  @behaviour AIBrain.Channel.Adapter

  def channel, do: :telegram

  @impl true
  def init(opts) do
    bot_token = Keyword.get(opts, :bot_token)
    chat_id = Keyword.get(opts, :chat_id)

    cond do
      is_nil(bot_token) -> {:error, :missing_bot_token}
      is_nil(chat_id) -> {:error, :missing_chat_id}
      true -> {:ok, %{bot_token: strip_bot_prefix(bot_token), chat_id: chat_id}}
    end
  end

  defp strip_bot_prefix("bot" <> rest), do: rest
  defp strip_bot_prefix(token), do: token

  @impl true
  def handle_inbound(state, %{"message" => %{"text" => text}}) do
    messages = [%{role: "user", content: text}]
    {:ok, messages, state}
  end

  def handle_inbound(state, %{"message" => %{"caption" => caption}}) when is_binary(caption) do
    messages = [%{role: "user", content: caption}]
    {:ok, messages, state}
  end

  def handle_inbound(state, _payload) do
    {:ok, [], state}
  end

  @impl true
  def send_message(state, %{type: :approval, approval_id: id, tool_name: tool_name, input: input}) do
    require Logger
    Logger.info("TelegramAdapter: Sending approval request #{id} to chat #{state.chat_id}")

    input_preview =
      input
      |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
      |> Enum.join("\n")

    text = """
    ⚠️ *需要审批* `[#{id}]`
    操作：`#{tool_name}`
    参数：
    #{input_preview}
    """

    keyboard = %{
      "inline_keyboard" => [
        [
          %{"text" => "✅ 批准", "callback_data" => "ia:a:#{id}"},
          %{"text" => "❌ 拒绝", "callback_data" => "ia:d:#{id}"}
        ]
      ]
    }

    url = "https://api.telegram.org/bot#{state.bot_token}/sendMessage"
    body = %{chat_id: state.chat_id, text: text, reply_markup: keyboard}

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        Logger.info("TelegramAdapter: Approval message sent successfully to #{state.chat_id}")
        {:ok, state}

      {:ok, %{body: %{"ok" => false, "description" => desc}}} ->
        Logger.error("TelegramAdapter: Failed to send approval message: #{desc}")
        {:error, desc}

      {:ok, %{status: status}} ->
        Logger.error(
          "TelegramAdapter: Unexpected HTTP #{status} for approval to #{state.chat_id}"
        )

        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("TelegramAdapter: Failed to send approval message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def send_message(state, %{content: content}) when is_binary(content) do
    require Logger
    Logger.info("TelegramAdapter: Sending message to chat #{state.chat_id}")

    url = "https://api.telegram.org/bot#{state.bot_token}/sendMessage"

    # Try with Markdown first — if Telegram rejects it (parse error), fall back to plain text
    case send_telegram(url, state.chat_id, content, "Markdown") do
      {:ok, _} ->
        {:ok, state}

      {:error, _} ->
        Logger.info("TelegramAdapter: Retrying without markdown for #{state.chat_id}")

        case send_telegram(url, state.chat_id, content, nil) do
          {:ok, _} -> {:ok, state}
          error -> error
        end
    end
  end

  def send_message(state, %{type: :interaction} = msg) do
    send_interaction(
      state,
      msg.interaction_type,
      msg.interaction_id,
      msg.schema,
      Map.get(msg, :reason, "")
    )
  end

  def send_message(state, _message), do: {:ok, state}

  # ── Interaction Helpers ──

  defp send_interaction(state, "confirm", id, schema, reason) do
    text = """
    ⚠️ *需要你的决定* `[#{String.slice(id, 0, 8)}]`

    #{schema[:title] || "确认"}

    #{schema[:prompt] || ""}
    #{if reason != "", do: "\n原因: #{reason}"}
    """

    keyboard = %{
      "inline_keyboard" => [
        [
          %{"text" => "✅ 批准", "callback_data" => "ia:a:#{id}"},
          %{"text" => "❌ 拒绝", "callback_data" => "ia:d:#{id}"}
        ]
      ]
    }

    send_telegram_with_keyboard(state, text, keyboard)
  end

  defp send_interaction(state, "select", id, schema, reason) do
    options =
      schema[:fields]
      |> List.wrap()
      |> Enum.find(%{}, fn f -> is_map(f) && f[:key] == :choice end)
      |> Map.get(:options, [])

    text = """
    ⚠️ *请选择* `[#{String.slice(id, 0, 8)}]`

    #{schema[:title] || "选择"}

    #{schema[:prompt] || ""}
    #{if reason != "", do: "\n原因: #{reason}"}
    """

    keyboard_rows =
      options
      |> Enum.with_index()
      |> Enum.chunk_every(2)
      |> Enum.map(fn chunk ->
        Enum.map(chunk, fn {opt, idx} ->
          %{"text" => "#{idx + 1}. #{opt}", "callback_data" => "ia:s:#{id}:#{idx}"}
        end)
      end)

    keyboard = %{"inline_keyboard" => keyboard_rows}
    send_telegram_with_keyboard(state, text, keyboard)
  end

  defp send_interaction(state, "text_input", id, schema, reason) do
    text = """
    ✍️ *需要你提供信息* `[#{String.slice(id, 0, 8)}]`

    #{schema[:title] || "信息"}

    #{schema[:prompt] || ""}
    #{if reason != "", do: "\n原因: #{reason}"}

    ---
    请直接回复这条消息来填写信息。
    """

    send_telegram(state, text)
  end

  defp send_interaction(state, "form", id, schema, reason) do
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

    text = """
    📋 *需要填写表单* `[#{String.slice(id, 0, 8)}]`

    #{schema[:title] || "表单"}

    #{schema[:prompt] || ""}
    #{if reason != "", do: "\n原因: #{reason}"}

    字段:
    #{fields_text}

    ---
    请回复每条字段的信息。
    """

    send_telegram(state, text)
  end

  defp send_interaction(state, _type, id, _schema, _reason) do
    send_telegram(state, "⚠️ Interaction #{String.slice(id || "", 0, 8)} requires your attention.")
  end

  defp send_telegram(state, content) do
    url = "https://api.telegram.org/bot#{state.bot_token}/sendMessage"
    body = %{chat_id: state.chat_id, text: content}

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} -> {:ok, state}
      {:ok, %{body: %{"ok" => false, "description" => desc}}} -> {:error, desc}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_telegram_with_keyboard(state, text, keyboard) do
    url = "https://api.telegram.org/bot#{state.bot_token}/sendMessage"
    body = %{chat_id: state.chat_id, text: text, parse_mode: "Markdown", reply_markup: keyboard}

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        {:ok, state}

      {:ok, %{body: %{"ok" => false, "description" => _desc}}} ->
        # Fallback to plain text
        body2 = %{chat_id: state.chat_id, text: text, reply_markup: keyboard}

        case Req.post(url, json: body2) do
          {:ok, %{status: 200, body: %{"ok" => true}}} -> {:ok, state}
          {:ok, %{body: %{"ok" => false, "description" => desc2}}} -> {:error, desc2}
          {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_telegram(url, chat_id, content, parse_mode) do
    body = %{chat_id: chat_id, text: content}
    body = if parse_mode, do: Map.put(body, :parse_mode, parse_mode), else: body

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        {:ok, %{}}

      {:ok, %{body: %{"ok" => false, "description" => desc}}} ->
        {:error, desc}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
