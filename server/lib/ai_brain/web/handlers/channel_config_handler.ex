defmodule AIBrain.Web.Handlers.ChannelConfigHandler do
  @moduledoc """
  HTTP handler for channel configuration management.
  Single table for all 5 platforms: telegram, discord, feishu, wechat, whatsapp.
  """

  import Plug.Conn
  require Logger
  alias AIBrain.Data.ChannelConfigs

  def handle_list(conn, params) do
    channel_type = Map.get(params, "channel_type")

    result =
      if channel_type && channel_type != "" && channel_type != "all" do
        ChannelConfigs.list(channel_type)
      else
        ChannelConfigs.list_all()
      end

    case result do
      {:ok, configs} ->
        masked = Enum.map(configs, &mask/1)
        json_response(conn, 200, %{configs: masked})
    end
  end

  def handle_get(conn, id, _params) do
    case ChannelConfigs.get(id) do
      {:ok, config} -> json_response(conn, 200, mask(config))
      {:error, :not_found} -> json_response(conn, 404, %{error: "Configuration not found"})
    end
  end

  def handle_create(conn, params) do
    attrs = %{
      id: Map.get(params, "id"),
      name: Map.get(params, "name"),
      channel_type: Map.get(params, "channel_type"),
      credentials: Jason.encode!(extract_credentials(params)),
      extra: Jason.encode!(extract_extra(params)),
      enabled: Map.get(params, "enabled", false)
    }

    case ChannelConfigs.create(attrs) do
      {:ok, config} ->
        reload_gateway_adapters()
        json_response(conn, 201, %{ok: true, id: config.id})

      {:error, changeset} ->
        errors = Enum.map(changeset.errors, fn {k, {msg, _}} -> "#{k}: #{msg}" end)
        json_response(conn, 422, %{error: "Validation failed", details: errors})
    end
  end

  def handle_update(conn, id, params) do
    attrs =
      %{
        name: Map.get(params, "name"),
        channel_type: Map.get(params, "channel_type"),
        credentials: Map.get(params, "credentials"),
        extra: Map.get(params, "extra"),
        enabled: Map.get(params, "enabled")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # If the frontend sends flat fields, convert to credentials JSON
    attrs = maybe_encode_flat_fields(params, attrs)

    case ChannelConfigs.update(id, attrs) do
      {:ok, config} ->
        reload_gateway_adapters()
        json_response(conn, 200, %{ok: true, id: config.id})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Configuration not found"})

      {:error, changeset} ->
        errors = Enum.map(changeset.errors, fn {k, {msg, _}} -> "#{k}: #{msg}" end)
        json_response(conn, 422, %{error: "Validation failed", details: errors})
    end
  end

  def handle_delete(conn, id) do
    case ChannelConfigs.delete(id) do
      {:ok, _} ->
        reload_gateway_adapters()
        json_response(conn, 200, %{ok: true})

      {:error, :not_found} ->
        json_response(conn, 404, %{error: "Configuration not found"})
    end
  end

  # ── Helpers ────────────────────────────────────────────

  defp mask(config) do
    creds = decode_json(config.credentials)
    extra = decode_json(config.extra)

    Map.merge(creds, extra)
    |> Map.merge(%{
      id: config.id,
      name: config.name,
      channel_type: config.channel_type,
      enabled: config.enabled,
      inserted_at: config.inserted_at
    })
  end

  defp extract_credentials(params) do
    creds = %{}

    creds =
      if params["bot_token"], do: Map.put(creds, "bot_token", params["bot_token"]), else: creds

    creds = if params["app_id"], do: Map.put(creds, "app_id", params["app_id"]), else: creds

    creds =
      if params["app_secret"], do: Map.put(creds, "app_secret", params["app_secret"]), else: creds

    creds =
      if params["webhook_secret"],
        do: Map.put(creds, "webhook_secret", params["webhook_secret"]),
        else: creds

    creds =
      if params["application_id"],
        do: Map.put(creds, "application_id", params["application_id"]),
        else: creds

    creds
  end

  defp extract_extra(params) do
    extra = %{}
    extra = if params["chat_id"], do: Map.put(extra, "chat_id", params["chat_id"]), else: extra

    extra =
      if params["allowed_guild_ids"],
        do: Map.put(extra, "allowed_guild_ids", params["allowed_guild_ids"]),
        else: extra

    extra =
      if params["verification_token"],
        do: Map.put(extra, "verification_token", params["verification_token"]),
        else: extra

    extra =
      if params["phone_number_id"],
        do: Map.put(extra, "phone_number_id", params["phone_number_id"]),
        else: extra

    extra =
      if params["business_account_id"],
        do: Map.put(extra, "business_account_id", params["business_account_id"]),
        else: extra

    extra
  end

  defp maybe_encode_flat_fields(params, attrs) do
    flat_keys = ~w(bot_token app_id app_secret webhook_secret application_id chat_id)
    has_flat = Enum.any?(flat_keys, &Map.has_key?(params, &1))

    if has_flat do
      creds = extract_credentials(params)
      extra = extract_extra(params)

      attrs =
        if map_size(creds) > 0 do
          Map.put(attrs, :credentials, Jason.encode!(creds))
        else
          attrs
        end

      attrs =
        if map_size(extra) > 0 do
          Map.put(attrs, :extra, Jason.encode!(extra))
        else
          attrs
        end

      attrs
    else
      attrs
    end
  end

  defp decode_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp decode_json(_), do: %{}

  defp reload_gateway_adapters do
    try do
      AIBrain.TelegramConfigLoader.load_and_register()
    rescue
      e ->
        Logger.warning("Failed to reload gateway adapters: #{Exception.message(e)}")
    end
  end

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
