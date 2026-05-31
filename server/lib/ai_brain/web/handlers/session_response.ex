defmodule AIBrain.Web.Handlers.Session.Response do
  @moduledoc """
  Session response - explicit structure, NO guessing.

  Replaces scattered map responses.
  """

  defstruct [
    :status,
    :data,
    :error
  ]

  @type t :: %__MODULE__{
          status: pos_integer(),
          data: map(),
          error: String.t() | nil
        }

  @doc """
  Create success response.
  """
  def success(status, data) when is_integer(status) and is_map(data) do
    %__MODULE__{
      status: status,
      data: data,
      error: nil
    }
  end

  @doc """
  Create error response.
  """
  def error(status, message) when is_integer(status) and is_binary(message) do
    %__MODULE__{
      status: status,
      data: %{error: message},
      error: message
    }
  end

  @doc """
  Create not found response.
  """
  def not_found(resource_id) do
    error(404, "#{resource_type(resource_id)} not found")
  end

  @doc """
  Create session not found response.
  """
  def session_not_found(session_id) do
    error(404, "Session not found")
    |> Map.put(:data, %{session_id: session_id})
  end

  @doc """
  Create bad request response.
  """
  def bad_request(message) do
    error(400, message)
  end

  @doc """
  Create internal error response.
  """
  def internal_error(message) do
    error(500, message)
  end

  @doc """
  Convert to JSON response via Plug.Conn.
  """
  def send_json(%__MODULE__{} = response, conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(response.status, Jason.encode!(response.data))
  end

  # ── Private ─────────────────────────────────────────────────────

  defp resource_type(_id), do: "Resource"
end
