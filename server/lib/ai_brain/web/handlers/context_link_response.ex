defmodule AIBrain.Web.Handlers.ContextLink.Response do
  @moduledoc """
  ContextLink response - explicit structure, NO guessing.

  Replaces scattered map responses.
  """

  defstruct [
    :status,
    :data
  ]

  @type t :: %__MODULE__{
          status: pos_integer(),
          data: map()
        }

  @doc """
  Create success response.
  """
  def success(status, data) when is_integer(status) and is_map(data) do
    %__MODULE__{
      status: status,
      data: data
    }
  end

  @doc """
  Create error response.
  """
  def error(status, message) when is_integer(status) and is_binary(message) do
    %__MODULE__{
      status: status,
      data: %{error: message}
    }
  end

  @doc """
  Create not found response.
  """
  def not_found do
    error(404, "ContextLink not found")
  end

  @doc """
  Create validation error response.
  """
  def validation_error(reason) when is_binary(reason) do
    error(422, reason)
  end

  @doc """
  Create bad request response.
  """
  def bad_request(message) when is_binary(message) do
    error(400, message)
  end

  @doc """
  Create internal error response.
  """
  def internal_error(message) when is_binary(message) do
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
end
