defmodule AIBrain.Web.Handlers.GoogleAuthHandler do
  @moduledoc """
  Google OAuth2 flow for Gmail and Calendar.

  Flow:
    1. GET /api/v1/auth/google → redirect to Google consent screen
    2. GET /api/v1/auth/google/callback → exchange code for tokens
    3. Tokens stored in system_settings, loaded into app env
  """

  import Plug.Conn
  require Logger

  @scopes ~w(https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar)

  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"

  def handle_authorize(conn) do
    config = oauth_config()

    if !config[:client_id] || !config[:client_secret] do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        400,
        Jason.encode!(%{
          error: "Google OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET."
        })
      )
    else
      redirect_uri = callback_url(conn)
      state = generate_state()

      # Store state in session for CSRF protection
      conn = put_session(conn, :oauth_state, state)

      params = %{
        client_id: config[:client_id],
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: Enum.join(@scopes, " "),
        access_type: "offline",
        prompt: "consent",
        state: state
      }

      url = "#{@auth_url}?#{URI.encode_query(params)}"

      conn
      |> put_resp_header("location", url)
      |> send_resp(302, "")
    end
  end

  def handle_callback(conn, %{"code" => code, "state" => state}) do
    # Verify state for CSRF protection
    stored_state = get_session(conn, :oauth_state)

    if state != stored_state do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(
        400,
        "<h3>OAuth failed: invalid state (CSRF mismatch)</h3><p>You can close this tab.</p>"
      )
    else
      config = oauth_config()
      redirect_uri = callback_url(conn)

      case exchange_code(config, code, redirect_uri) do
        {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token}} ->
          store_tokens(access_token, refresh_token)
          load_tokens_into_env()

          Logger.info("Google OAuth: tokens stored and loaded successfully")

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(
            200,
            "<h3>Connected!</h3><p>Google account linked. You can close this tab.</p>"
          )

        {:ok, %{"access_token" => access_token}} ->
          # No refresh_token — user didn't grant offline access
          store_tokens(access_token, nil)
          load_tokens_into_env()

          Logger.info("Google OAuth: access token stored (no refresh token)")

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(
            200,
            "<h3>Connected!</h3><p>Google account linked (no offline access). You can close this tab.</p>"
          )

        {:error, reason} ->
          Logger.warning("Google OAuth: token exchange failed: #{inspect(reason)}")

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(
            400,
            "<h3>OAuth failed</h3><p>#{inspect(reason)}</p><p>You can close this tab.</p>"
          )
      end
    end
  end

  def handle_callback(conn, %{"error" => error}) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(400, "<h3>OAuth denied</h3><p>#{error}</p><p>You can close this tab.</p>")
  end

  def handle_callback(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(400, "<h3>OAuth failed</h3><p>Missing authorization code.</p>")
  end

  def handle_status(conn) do
    connected = AIBrain.Data.SystemSetting.get("google_access_token") != {:error, :not_found}
    has_refresh = AIBrain.Data.SystemSetting.get("google_refresh_token") != {:error, :not_found}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        connected: connected,
        has_refresh_token: has_refresh
      })
    )
  end

  def handle_disconnect(conn) do
    AIBrain.Data.SystemSetting.set("google_access_token", "")
    AIBrain.Data.SystemSetting.set("google_refresh_token", "")

    # Clear from app env
    Application.put_env(:ai_brain, :email, Map.put(email_config(), :gmail_token, nil))
    Application.put_env(:ai_brain, :calendar, Map.put(calendar_config(), :google_token, nil))

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{ok: true}))
  end

  # -- Token management --

  def load_tokens_into_env do
    token =
      case AIBrain.Data.SystemSetting.get("google_access_token") do
        {:ok, t} when is_binary(t) and t != "" -> t
        _ -> nil
      end

    if token do
      Application.put_env(:ai_brain, :email, Map.put(email_config(), :gmail_token, token))
      Application.put_env(:ai_brain, :calendar, Map.put(calendar_config(), :google_token, token))
      Logger.info("Google tokens loaded into app env")
    end
  end

  def refresh_access_token do
    config = oauth_config()

    refresh_token =
      case AIBrain.Data.SystemSetting.get("google_refresh_token") do
        {:ok, t} when is_binary(t) and t != "" -> t
        _ -> nil
      end

    if !refresh_token || !config[:client_id] || !config[:client_secret] do
      {:error, :no_refresh_token}
    else
      case Req.post(@token_url,
             form: %{
               client_id: config[:client_id],
               client_secret: config[:client_secret],
               refresh_token: refresh_token,
               grant_type: "refresh_token"
             }
           ) do
        {:ok, %{status: 200, body: %{"access_token" => new_token}}} ->
          AIBrain.Data.SystemSetting.set("google_access_token", new_token)
          load_tokens_into_env()
          {:ok, new_token}

        {:ok, %{status: s, body: b}} ->
          {:error, "Token refresh failed HTTP #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -- Private --

  defp exchange_code(config, code, redirect_uri) do
    case Req.post(@token_url,
           form: %{
             client_id: config[:client_id],
             client_secret: config[:client_secret],
             code: code,
             redirect_uri: redirect_uri,
             grant_type: "authorization_code"
           }
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: s, body: b}} -> {:error, "HTTP #{s}: #{inspect(b)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_tokens(access_token, refresh_token) do
    AIBrain.Data.SystemSetting.set("google_access_token", access_token)
    if refresh_token, do: AIBrain.Data.SystemSetting.set("google_refresh_token", refresh_token)
  end

  defp oauth_config do
    %{
      client_id:
        System.get_env("GOOGLE_CLIENT_ID") || Application.get_env(:ai_brain, :google_client_id),
      client_secret:
        System.get_env("GOOGLE_CLIENT_SECRET") ||
          Application.get_env(:ai_brain, :google_client_secret)
    }
  end

  defp callback_url(conn) do
    port = conn.port
    scheme = if port == 443, do: "https", else: "http"
    default = "#{scheme}://#{conn.host}#{if port not in [80, 443], do: ":#{port}", else: ""}"
    base = Application.get_env(:ai_brain, :base_url, default)
    "#{base}/api/v1/auth/google/callback"
  end

  defp generate_state do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp email_config, do: Application.get_env(:ai_brain, :email, %{})
  defp calendar_config, do: Application.get_env(:ai_brain, :calendar, %{})
end
