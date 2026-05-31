defmodule AIBrain.Business.Email do
  @moduledoc """
  Unified email business layer.

  Provides a single entry point for email operations, automatically
  routing to the correct backend (Gmail, Outlook, SMTP, IMAP) based
  on configuration.

  The Tool layer should call these functions — never call backend clients directly.
  """

  alias AIBrain.Business.Email.{GmailClient, OutlookClient, SmtpSender}

  # -- Public API --

  def send(to, subject, body) do
    case detect_send_backend() do
      :gmail -> GmailClient.send(to, subject, body)
      :outlook -> OutlookClient.send(to, subject, body)
      :smtp -> SmtpSender.send(to, subject, body)
      nil -> {:error, "No email send backend configured"}
    end
  end

  def read_inbox(max \\ 10, query \\ nil) do
    case detect_read_backend() do
      :gmail ->
        GmailClient.read_inbox(max, query)

      :outlook ->
        OutlookClient.read_inbox(max, query)

      :imap ->
        {:error,
         "IMAP direct not implemented. Configure :rest_inbox_url, :gmail_token, or :outlook_token"}

      :rest ->
        read_rest_inbox(max)

      nil ->
        {:error, "No email read backend configured"}
    end
  end

  def search(query, max \\ 10) do
    case detect_read_backend() do
      :gmail -> GmailClient.read_inbox(max, query)
      :outlook -> OutlookClient.read_inbox(max, query)
      _ -> {:error, "Search requires Gmail or Outlook API (not available with IMAP)"}
    end
  end

  def reply(message_id, body, opts \\ %{}) do
    case detect_send_backend() do
      :gmail -> GmailClient.reply(message_id, body)
      :outlook -> OutlookClient.reply(message_id, body)
      :smtp -> smtp_reply(message_id, body, opts)
      nil -> {:error, "No reply backend configured"}
    end
  end

  def mark_read(message_id) do
    case detect_read_backend() do
      :gmail -> GmailClient.mark_read(message_id)
      :outlook -> OutlookClient.mark_read(message_id)
      _ -> {:error, "mark_read not supported for this backend"}
    end
  end

  def archive(message_id) do
    case detect_read_backend() do
      :gmail -> GmailClient.archive(message_id)
      :outlook -> OutlookClient.archive(message_id)
      _ -> {:error, "Archive not supported for this backend"}
    end
  end

  # -- Backend Detection --

  def detect_send_backend do
    cond do
      configured?(:gmail_token) -> :gmail
      configured?(:outlook_token) -> :outlook
      configured?(:smtp_relay) or configured?(:smtp_server) -> :smtp
      true -> nil
    end
  end

  def detect_read_backend do
    cond do
      configured?(:gmail_token) -> :gmail
      configured?(:outlook_token) -> :outlook
      configured?(:imap_server) -> :imap
      configured?(:rest_inbox_url) -> :rest
      true -> nil
    end
  end

  # -- REST inbox fallback --

  defp read_rest_inbox(max) do
    url = config()[:rest_inbox_url]

    case Req.get(url, headers: [{"Accept", "application/json"}]) do
      {:ok, %{status: 200, body: body}} ->
        emails = body["messages"] || body["emails"] || body["value"] || []
        {:ok, %{"emails" => Enum.take(emails, max), "count" => length(emails)}}

      {:ok, %{status: s}} ->
        {:error, "REST inbox returned #{s}"}

      {:error, reason} ->
        {:error, "REST inbox error: #{inspect(reason)}"}
    end
  end

  defp smtp_reply(message_id, body, opts) do
    to = map_get(opts, "to") || map_get(opts, :to)
    subject = map_get(opts, "subject") || map_get(opts, :subject)

    cond do
      not is_binary(to) or String.trim(to) == "" ->
        {:error,
         "SMTP reply requires recipient 'to' because message_id cannot be resolved via SMTP"}

      not is_binary(subject) or String.trim(subject) == "" ->
        {:error, "SMTP reply requires subject because message_id cannot be resolved via SMTP"}

      true ->
        subject =
          if String.starts_with?(String.downcase(subject), "re:"),
            do: subject,
            else: "Re: #{subject}"

        body =
          if is_binary(message_id) and message_id != "" do
            "#{body}\n\nOn message #{message_id}"
          else
            body
          end

        SmtpSender.send(to, subject, body)
    end
  end

  defp map_get(map, key) when is_map(map), do: Map.get(map, key)
  defp map_get(_, _), do: nil

  # -- Helpers --

  defp configured?(key),
    do: Map.has_key?(config(), key) and config()[key] != nil

  def config, do: Application.get_env(:ai_brain, :email, %{})
end
