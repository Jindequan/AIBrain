defmodule AIBrain.Data.JSONMap do
  @moduledoc """
  Custom Ecto type for map fields that handles empty strings.

  This type converts empty strings to empty maps when loading from database.
  """

  use Ecto.Type

  def type, do: :map

  def cast(value) when is_map(value), do: {:ok, value}
  def cast(""), do: {:ok, %{}}
  def cast(nil), do: {:ok, %{}}
  def cast(_), do: :error

  def load(value) when is_map(value), do: {:ok, value}
  def load(""), do: {:ok, %{}}
  def load(nil), do: {:ok, %{}}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:ok, %{}}
    end
  end

  def load(_), do: {:ok, %{}}

  def dump(value) when is_map(value), do: {:ok, value}
  def dump(""), do: {:ok, %{}}
  def dump(nil), do: {:ok, %{}}
  def dump(_), do: :error
end
