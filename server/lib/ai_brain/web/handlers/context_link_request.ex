defmodule AIBrain.Web.Handlers.ContextLink.Request do
  @moduledoc """
  ContextLink request - explicit structure, NO guessing.

  Replaces scattered params["xxx"] access.
  """

  defstruct [
    :id,
    :project_id,
    :context_type,
    :owner_type,
    :owner_id
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          project_id: String.t() | nil,
          context_type: String.t() | nil,
          owner_type: String.t() | nil,
          owner_id: String.t() | nil
        }

  @type request_type :: :list | :get | :create | :delete

  @doc """
  Build request from params (for list).
  """
  def build_from_params(params) do
    %__MODULE__{
      project_id: params["project_id"],
      context_type: params["context_type"],
      owner_type: params["owner_type"],
      owner_id: params["owner_id"]
    }
  end

  @doc """
  Build request for create.
  """
  def build_for_create(params) do
    %__MODULE__{
      project_id: params["project_id"],
      context_type: params["context_type"],
      owner_type: params["owner_type"],
      owner_id: params["owner_id"]
    }
  end

  @doc """
  Validate request based on type.
  """
  def validate(%__MODULE__{} = request, type) do
    case type do
      :create -> validate_create(request)
      :list -> :ok
      :get -> validate_get(request)
      :delete -> validate_delete(request)
    end
  end

  @doc """
  Convert to ContextLinks opts.
  """
  def to_context_links_opts(%__MODULE__{} = request) do
    []
    |> put_if_not_nil(:project_id, request.project_id)
    |> put_if_not_nil(:context_type, request.context_type)
    |> put_if_not_nil(:owner_type, request.owner_type)
    |> put_if_not_nil(:owner_id, request.owner_id)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp validate_create(%__MODULE__{} = request) do
    cond do
      is_nil(request.project_id) ->
        {:error, :missing_project_id}

      is_nil(request.context_type) ->
        {:error, :missing_context_type}

      is_nil(request.owner_type) ->
        {:error, :missing_owner_type}

      is_nil(request.owner_id) ->
        {:error, :missing_owner_id}

      true ->
        :ok
    end
  end

  defp validate_get(%__MODULE__{id: id}) when is_binary(id), do: :ok
  defp validate_get(%__MODULE__{}), do: {:error, :missing_id}

  defp validate_delete(%__MODULE__{id: id}) when is_binary(id), do: :ok
  defp validate_delete(%__MODULE__{}), do: {:error, :missing_id}

  defp put_if_not_nil(opts, _key, nil), do: opts
  defp put_if_not_nil(opts, key, value), do: Keyword.put(opts, key, value)
end
