defmodule AIBrain.Business.Email.GmailClient do
  @moduledoc """
  Gmail API client for send, read, reply, mark_read, and archive.
  """

  @gmail_api "https://gmail.googleapis.com/gmail/v1/users/me"

  def send(to, subject, body) do
    token = get_token()

    if !token do
      {:error, "Gmail OAuth token not configured"}
    else
      raw = AIBrain.Business.Email.MimeBuilder.build_send_mime(to, subject, body)
      encoded = Base.encode64(raw)

      case Req.post("#{@gmail_api}/messages/send",
             headers: auth_headers(token),
             json: %{raw: encoded}
           ) do
        {:ok, %{status: 200, body: resp}} ->
          {:ok, "Sent to #{to}: #{resp["id"]}"}

        {:ok, %{status: s, body: b}} ->
          {:error, "Gmail send failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Gmail send error: #{inspect(reason)}"}
      end
    end
  end

  def read_inbox(max, query \\ nil) do
    token = get_token()

    if !token do
      {:error, "Gmail OAuth token not configured"}
    else
      params = %{maxResults: max}
      params = if query, do: Map.put(params, :q, query), else: params

      case Req.get("#{@gmail_api}/messages", headers: auth_headers(token), params: params) do
        {:ok, %{status: 200, body: %{"messages" => msgs}}} when is_list(msgs) ->
          emails =
            Enum.map(Enum.take(msgs, max), &fetch_message_metadata(&1["id"], token))
            |> Enum.reject(&is_nil/1)

          {:ok, %{"emails" => emails, "count" => length(emails)}}

        {:ok, %{status: 200}} ->
          {:ok, %{"emails" => [], "count" => 0}}

        {:ok, %{status: s, body: b}} ->
          {:error, "Gmail inbox failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Gmail inbox error: #{inspect(reason)}"}
      end
    end
  end

  def reply(message_id, body) do
    token = get_token()

    if !token do
      {:error, "Gmail OAuth token not configured"}
    else
      original = fetch_full_message(message_id, token)

      if !original do
        {:error, "Original message not found: #{message_id}"}
      else
        raw = AIBrain.Business.Email.MimeBuilder.build_reply_mime(original, body)
        encoded = Base.encode64(raw)

        case Req.post("#{@gmail_api}/messages/send",
               headers: auth_headers(token),
               json: %{raw: encoded, threadId: original["threadId"]}
             ) do
          {:ok, %{status: 200, body: resp}} -> {:ok, "Reply sent: #{resp["id"]}"}
          {:ok, %{status: s, body: b}} -> {:error, "Gmail reply failed HTTP #{s}: #{inspect(b)}"}
          {:error, reason} -> {:error, "Gmail reply error: #{inspect(reason)}"}
        end
      end
    end
  end

  def mark_read(message_id) do
    token = get_token()

    if !token do
      {:error, "Gmail OAuth token not configured"}
    else
      case Req.post("#{@gmail_api}/messages/#{message_id}/modify",
             headers: auth_headers(token),
             json: %{removeLabelIds: ["UNREAD"]}
           ) do
        {:ok, %{status: 200}} ->
          {:ok, "Marked as read: #{message_id}"}

        {:ok, %{status: s, body: b}} ->
          {:error, "Gmail mark_read failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Gmail mark_read error: #{inspect(reason)}"}
      end
    end
  end

  def archive(message_id) do
    token = get_token()

    if !token do
      {:error, "Gmail OAuth token not configured"}
    else
      case Req.post("#{@gmail_api}/messages/#{message_id}/modify",
             headers: auth_headers(token),
             json: %{removeLabelIds: ["INBOX"]}
           ) do
        {:ok, %{status: 200}} -> {:ok, "Archived: #{message_id}"}
        {:ok, %{status: s, body: b}} -> {:error, "Gmail archive failed HTTP #{s}: #{inspect(b)}"}
        {:error, reason} -> {:error, "Gmail archive error: #{inspect(reason)}"}
      end
    end
  end

  # -- Internal --

  def fetch_message_metadata(msg_id, token) do
    case Req.get("#{@gmail_api}/messages/#{msg_id}",
           headers: auth_headers(token),
           params: %{format: "metadata", metadataHeaders: "From,Subject,Date"}
         ) do
      {:ok, %{status: 200, body: msg}} ->
        headers = (msg["payload"] || %{})["headers"] || []

        %{
          "id" => msg["id"],
          "threadId" => msg["threadId"],
          "from" => AIBrain.Business.Email.MimeBuilder.header_val(headers, "From"),
          "subject" => AIBrain.Business.Email.MimeBuilder.header_val(headers, "Subject"),
          "date" => AIBrain.Business.Email.MimeBuilder.header_val(headers, "Date"),
          "snippet" => msg["snippet"] || ""
        }

      _ ->
        nil
    end
  end

  defp fetch_full_message(msg_id, token) do
    case Req.get("#{@gmail_api}/messages/#{msg_id}", headers: auth_headers(token)) do
      {:ok, %{status: 200, body: msg}} -> msg
      _ -> nil
    end
  end

  defp auth_headers(token),
    do: [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

  defp get_token, do: AIBrain.Business.Email.config()[:gmail_token]
end
