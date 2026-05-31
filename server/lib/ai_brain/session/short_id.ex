defmodule AIBrain.Session.ShortID do
  @moduledoc """
  Short ID generation using a subset of URL-safe characters.

  Provides compact, user-friendly identifiers that are:
  - URL-safe (no special characters that need encoding)
  - Human-readable (easy to copy, share, and debug)
  - Sufficiently unique (collision-resistant for personal use)
  """

  @alphabet "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @prefixes %{
    session: "s",
    message: "m",
    tool_use: "t",
    file: "f"
  }

  @doc """
  Generate a short ID with the given length and optional prefix.

  ## Examples

      iex> ShortID.generate(8)
      "xY7bN9pQ2"

      iex> ShortID.generate(:session, 8)
      "s_xY7bN9pQ2"

      iex> ShortID.generate(:message, 6)
      "m_a1B2c3"

  """
  def generate(length, prefix \\ nil)

  def generate(length, prefix) when is_integer(length) and length > 0 do
    prefix_part = if prefix, do: "#{prefix}_", else: ""
    random_part = generate_random(length)
    prefix_part <> random_part
  end

  def generate(type, length) when is_atom(type) do
    prefix = Map.get(@prefixes, type, "")
    generate(length, prefix)
  end

  @doc """
  Generate a session ID (session- + 24 hex characters).
  """
  def session_id() do
    "session-" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  @doc """
  Generate a run ID (run- + 24 hex characters).
  """
  def run_id() do
    "run-" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end

  @doc """
  Generate a message ID (m_ + 6 characters).
  """
  def message_id() do
    generate(:message, 6)
  end

  @doc """
  Generate a tool_use ID (t_ + 12 characters for uniqueness).
  """
  def tool_use_id() do
    generate(:tool_use, 12)
  end

  # ==================== Private Functions ====================

  defp generate_random(length) do
    :crypto.strong_rand_bytes(length)
    |> generate_random(<<>>)
  end

  defp generate_random(<<>>, acc), do: acc

  defp generate_random(<<byte::8, rest::binary>>, acc) do
    index = rem(byte, byte_size(@alphabet))
    char = :binary.at(@alphabet, index)
    generate_random(rest, <<acc::binary, char>>)
  end
end
