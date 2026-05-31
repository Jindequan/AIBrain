defmodule AIBrain.Data.ChannelConfigs do
  @moduledoc """
  Unified channel configuration CRUD. One table for all 5 platforms.
  """

  import Ecto.Query
  alias AIBrain.Repo
  alias AIBrain.Data.ChannelConfig

  def list_all do
    configs = Repo.all(ChannelConfig, order_by: [asc: :channel_type, asc: :name])
    {:ok, configs}
  end

  def list(channel_type) when is_binary(channel_type) do
    configs =
      ChannelConfig
      |> where([c], c.channel_type == ^channel_type)
      |> order_by([c], asc: c.name)
      |> Repo.all()

    {:ok, configs}
  end

  def list_enabled(channel_type) when is_binary(channel_type) do
    configs =
      ChannelConfig
      |> where([c], c.channel_type == ^channel_type and c.enabled == true)
      |> Repo.all()

    {:ok, configs}
  end

  def get(id) do
    case Repo.get(ChannelConfig, id) do
      nil -> {:error, :not_found}
      config -> {:ok, config}
    end
  end

  def create(attrs) do
    %ChannelConfig{}
    |> ChannelConfig.changeset(attrs)
    |> Repo.insert()
  end

  def update(id, attrs) do
    case get(id) do
      {:ok, config} ->
        config
        |> ChannelConfig.changeset(attrs)
        |> Repo.update()

      error ->
        error
    end
  end

  def delete(id) do
    case get(id) do
      {:ok, config} -> Repo.delete(config)
      error -> error
    end
  end
end
