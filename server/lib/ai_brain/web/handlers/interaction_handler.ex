defmodule AIBrain.Web.Handlers.InteractionHandler do
  @moduledoc """
  HTTP handler for interaction management.
  """

  import Plug.Conn

  alias AIBrain.Data.Interactions
  alias AIBrain.Interaction, as: InteractionFacade

  def handle_list(conn, params) do
    filters =
      []
      |> maybe_add_filter(params, "status")
      |> maybe_add_filter(params, "type")
      |> maybe_add_filter(params, "session_id")
      |> maybe_add_filter(params, "limit")

    interactions = Interactions.list(filters)
    json_response(conn, 200, %{interactions: interactions})
  end

  def handle_get(conn, id) do
    case Interactions.get(id) do
      nil ->
        json_response(conn, 404, %{error: "Interaction not found", id: id})

      interaction ->
        json_response(conn, 200, %{interaction: interaction})
    end
  end

  def handle_session_chain(conn, session_id) do
    chain = Interactions.chain_for_session(session_id)
    json_response(conn, 200, %{interactions: chain})
  end

  def handle_resolve(conn, id, params) do
    result = Map.get(params, "result", %{})
    resolved_by = Map.get(params, "resolved_by", AIBrain.Data.Users.default_user_id())

    case InteractionFacade.resolve(id, result, resolved_by) do
      :ok ->
        json_response(conn, 200, %{message: "Resolved", id: id})

      {:error, reason} ->
        json_response(conn, 422, %{error: reason, id: id})
    end
  end

  def handle_stop_proxy(conn, id, _params) do
    case Interactions.mark_need_manual(id, reason: "user_stopped_proxy") do
      {:ok, interaction} ->
        # Notify Proxy to discard result (if currently processing)
        AIBrain.Channel.Bus.publish(%{
          type: :proxy_cancelled,
          interaction_id: id
        })

        # Notify frontend that this needs manual handling
        AIBrain.Channel.Bus.publish(%{
          type: :interaction_escalated,
          interaction_id: id,
          reason: "user_stopped_proxy",
          proxy_trail: interaction.proxy_trail || []
        })

        json_response(conn, 200, %{
          message: "Proxy stopped for interaction",
          id: id,
          status: "need_manual"
        })

      {:error, reason} ->
        json_response(conn, 422, %{error: reason, id: id})
    end
  end

  defp maybe_add_filter(filters, params, "status") do
    case Map.get(params, "status") do
      nil -> filters
      value -> Keyword.put(filters, :status, value)
    end
  end

  defp maybe_add_filter(filters, params, "type") do
    case Map.get(params, "type") do
      nil -> filters
      value -> Keyword.put(filters, :type, value)
    end
  end

  defp maybe_add_filter(filters, params, "session_id") do
    case Map.get(params, "session_id") do
      nil -> filters
      value -> Keyword.put(filters, :session_id, value)
    end
  end

  defp maybe_add_filter(filters, params, "limit") do
    case Map.get(params, "limit") do
      nil -> filters
      value -> Keyword.put(filters, :limit, String.to_integer(value))
    end
  end

  defp maybe_add_filter(filters, _params, _key), do: filters

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
