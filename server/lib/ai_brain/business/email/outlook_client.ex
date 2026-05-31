defmodule AIBrain.Business.Email.OutlookClient do
  @moduledoc """
  Microsoft Graph API (Outlook) client for send, read, reply, mark_read, and archive.
  """

  @outlook_api "https://graph.microsoft.com/v1.0/me"

  def send(to, subject, body) do
    token = get_token()

    if !token do
      {:error, "Outlook OAuth token not configured"}
    else
      payload = %{
        message: %{
          subject: subject,
          body: %{contentType: "Text", content: body},
          toRecipients: [%{emailAddress: %{address: to}}]
        }
      }

      case Req.post("#{@outlook_api}/sendMail",
             headers: auth_headers(token),
             json: payload
           ) do
        {:ok, %{status: 202}} -> {:ok, "Sent to #{to}"}
        {:ok, %{status: s, body: b}} -> {:error, "Outlook send failed HTTP #{s}: #{inspect(b)}"}
        {:error, reason} -> {:error, "Outlook send error: #{inspect(reason)}"}
      end
    end
  end

  def read_inbox(max, query \\ nil) do
    token = get_token()

    if !token do
      {:error, "Outlook OAuth token not configured"}
    else
      params = %{:"$top" => max}
      params = if query, do: Map.put(params, :"$search", ~s("#{query}")), else: params

      case Req.get("#{@outlook_api}/messages", headers: auth_headers(token), params: params) do
        {:ok, %{status: 200, body: %{"value" => msgs}}} ->
          emails = Enum.map(msgs, &format_message/1)
          {:ok, %{"emails" => emails, "count" => length(emails)}}

        {:ok, %{status: s, body: b}} ->
          {:error, "Outlook inbox failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Outlook inbox error: #{inspect(reason)}"}
      end
    end
  end

  def reply(message_id, body) do
    token = get_token()

    if !token do
      {:error, "Outlook OAuth token not configured"}
    else
      payload = %{comment: body}

      case Req.post("#{@outlook_api}/messages/#{message_id}/reply",
             headers: auth_headers(token),
             json: payload
           ) do
        {:ok, %{status: 202}} -> {:ok, "Reply sent"}
        {:ok, %{status: s, body: b}} -> {:error, "Outlook reply failed HTTP #{s}: #{inspect(b)}"}
        {:error, reason} -> {:error, "Outlook reply error: #{inspect(reason)}"}
      end
    end
  end

  def mark_read(message_id) do
    token = get_token()

    if !token do
      {:error, "Outlook OAuth token not configured"}
    else
      case Req.patch("#{@outlook_api}/messages/#{message_id}",
             headers: auth_headers(token),
             json: %{isRead: true}
           ) do
        {:ok, %{status: 200}} ->
          {:ok, "Marked as read: #{message_id}"}

        {:ok, %{status: s, body: b}} ->
          {:error, "Outlook mark_read failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Outlook mark_read error: #{inspect(reason)}"}
      end
    end
  end

  def archive(message_id) do
    token = get_token()

    if !token do
      {:error, "Outlook OAuth token not configured"}
    else
      case Req.patch("#{@outlook_api}/messages/#{message_id}",
             headers: auth_headers(token),
             json: %{flag: %{flagStatus: "flagged"}}
           ) do
        {:ok, %{status: 200}} ->
          {:ok, "Archived (flagged): #{message_id}"}

        {:ok, %{status: s, body: b}} ->
          {:error, "Outlook archive failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "Outlook archive error: #{inspect(reason)}"}
      end
    end
  end

  # -- Helpers --

  defp format_message(msg) do
    %{
      "id" => msg["id"],
      "from" => format_recipient(msg["from"]),
      "subject" => msg["subject"],
      "date" => msg["receivedDateTime"],
      "snippet" => msg["bodyPreview"] || ""
    }
  end

  defp format_recipient(nil), do: nil
  defp format_recipient(%{"emailAddress" => %{"address" => addr}}), do: addr

  defp auth_headers(token),
    do: [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

  defp get_token, do: AIBrain.Business.Email.config()[:outlook_token]
end
