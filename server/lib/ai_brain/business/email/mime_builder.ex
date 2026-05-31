defmodule AIBrain.Business.Email.MimeBuilder do
  @moduledoc """
  MIME message construction helpers.

  Builds RFC2822 and MIME-encoded messages for sending emails
  and replies via Gmail raw message API.
  """

  @doc """
  Build a simple RFC2822 message for SMTP sending.
  """
  def build_rfc2822(from, to, subject, body) do
    date = DateTime.utc_now() |> DateTime.to_string()
    "From: #{from}\r\nTo: #{to}\r\nSubject: #{subject}\r\nDate: #{date}\r\n\r\n#{body}"
  end

  @doc """
  Build a MIME message for Gmail send API.
  """
  def build_send_mime(to, subject, body) do
    config = AIBrain.Business.Email.config()
    from = config[:username] || config[:email] || "user@example.com"

    "From: #{from}\r\nTo: #{to}\r\nSubject: #{subject}\r\n" <>
      "Content-Type: text/plain; charset=UTF-8\r\n\r\n#{body}"
  end

  @doc """
  Build a MIME reply message for Gmail send API.
  Preserves thread information via In-Reply-To and References headers.
  """
  def build_reply_mime(original, body) do
    config = AIBrain.Business.Email.config()
    from = config[:username] || config[:email] || "user@example.com"
    headers = (original["payload"] || %{})["headers"] || []
    orig_from = header_val(headers, "From")
    orig_subject = header_val(headers, "Subject") || ""
    refs = header_val(headers, "Message-ID") || ""

    reply_subject =
      if String.starts_with?(orig_subject, "Re:"), do: orig_subject, else: "Re: #{orig_subject}"

    "From: #{from}\r\nTo: #{orig_from}\r\nSubject: #{reply_subject}\r\n" <>
      "In-Reply-To: #{refs}\r\nReferences: #{refs}\r\n" <>
      "Content-Type: text/plain; charset=UTF-8\r\n\r\n#{body}"
  end

  @doc """
  Extract a header value from a list of Gmail-format headers.
  """
  def header_val(headers, name) do
    Enum.find_value(headers, fn h ->
      if String.downcase(h["name"] || "") == String.downcase(name), do: h["value"]
    end)
  end
end
