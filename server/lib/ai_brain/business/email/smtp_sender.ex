defmodule AIBrain.Business.Email.SmtpSender do
  @moduledoc """
  SMTP email sender via :gen_smtp_client.
  """

  def send(to, subject, body) do
    config = AIBrain.Business.Email.config()
    relay = config[:smtp_relay] || config[:smtp_server]
    port = config[:smtp_port] || 587
    username = config[:username] || config[:email]
    password = config[:password]

    if relay && username && password do
      do_send(relay, port, username, password, to, subject, body)
    else
      {:error, "SMTP not configured"}
    end
  end

  defp do_send(relay, port, username, password, to, subject, body) do
    message = AIBrain.Business.Email.MimeBuilder.build_rfc2822(username, to, subject, body)
    mail = {username, [to], message}
    opts = [relay: relay, port: port, username: username, password: password, auth: :auto]

    case :gen_smtp_client.send_blocking(mail, opts) do
      {:ok, receipt} -> {:ok, "Sent to #{to}: #{inspect(receipt)}"}
      {:error, reason} -> {:error, "Send failed: #{inspect(reason)}"}
    end
  end
end
