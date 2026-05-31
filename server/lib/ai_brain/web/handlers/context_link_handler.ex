defmodule AIBrain.Web.Handlers.ContextLinkHandler do
  @moduledoc """
  ContextLink HTTP handler - clean functional style.

  ## Responsibilities

  - HTTP request handling ONLY
  - No business logic (delegates to Request/Response)
  - Clear data flow

  ## Before vs After

  ### BEFORE (stinking mess):
  ```elixir
  def handle_list(conn, params) do
    opts = []
      |> maybe_put(:project_id, params["project_id"])
      |> maybe_put(:context_type, params["context_type"])
      |> maybe_put(:owner_type, params["owner_type"])
      |> maybe_put(:owner_id, params["owner_id"])

    {:ok, links} = ContextLinks.list(opts)
    json(conn, 200, %{context_links: links})
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  ```

  ### AFTER (clean functional):
  ```elixir
  def handle_list(conn, params) do
    request = Request.build_from_params(params)
    opts = Request.to_context_links_opts(request)

    {:ok, links} = ContextLinks.list(opts)
    Response.success(200, %{context_links: links})
    |> Response.send_json(conn)
  end
  ```
  """

  alias AIBrain.Web.Handlers.{ContextLink.Request, ContextLink.Response}
  alias AIBrain.Data.ContextLinks

  @doc """
  List context links with optional filters.
  """
  def handle_list(conn, params) do
    request = Request.build_from_params(params)
    opts = Request.to_context_links_opts(request)

    case ContextLinks.list(opts) do
      {:ok, links} ->
        Response.success(200, %{context_links: links})
        |> Response.send_json(conn)
    end
  end

  @doc """
  Get context link by ID.
  """
  def handle_get(conn, id) do
    case ContextLinks.get(id) do
      {:ok, link} ->
        Response.success(200, link)
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.not_found()
        |> Response.send_json(conn)
    end
  end

  @doc """
  Create new context link.
  """
  def handle_create(conn, params) do
    request = Request.build_for_create(params)

    case Request.validate(request, :create) do
      :ok ->
        case ContextLinks.create(params) do
          {:ok, link} ->
            Response.success(201, link)
            |> Response.send_json(conn)

          {:error, reason} ->
            Response.error(422, inspect(reason))
            |> Response.send_json(conn)
        end

      {:error, :missing_project_id} ->
        Response.bad_request("project_id required")
        |> Response.send_json(conn)

      {:error, :missing_context_type} ->
        Response.bad_request("context_type required")
        |> Response.send_json(conn)

      {:error, :missing_owner_type} ->
        Response.bad_request("owner_type required")
        |> Response.send_json(conn)

      {:error, :missing_owner_id} ->
        Response.bad_request("owner_id required")
        |> Response.send_json(conn)
    end
  end

  @doc """
  Delete context link.
  """
  def handle_delete(conn, id) do
    case ContextLinks.delete(id) do
      :ok ->
        Response.success(200, %{message: "Deleted"})
        |> Response.send_json(conn)

      {:error, :not_found} ->
        Response.not_found()
        |> Response.send_json(conn)
    end
  end
end
