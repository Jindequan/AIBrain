defmodule AIBrain.Web.Handlers.Session.Request do
  @moduledoc """
  Session request - explicit structure, NO guessing.

  Replaces scattered Map.get(params, ...) calls.
  """

  defstruct [
    :session_id,
    :messages,
    :model,
    :mode,
    :workspace_path,
    :goal_id,
    :channel_adapter,
    :channel_id,
    :title,
    :search_query
  ]

  @type t :: %__MODULE__{
          session_id: String.t() | nil,
          messages: list(map()),
          model: String.t() | nil,
          mode: atom(),
          workspace_path: String.t() | nil,
          goal_id: String.t() | nil,
          channel_adapter: atom() | nil,
          channel_id: String.t() | nil,
          title: String.t() | nil,
          search_query: String.t() | nil
        }

  @type request_type :: :create | :send_message | :resume | :update | :delete | :search

  @doc """
  Build request from params (for create/send_message).
  """
  def build_from_params(params) do
    messages = extract_messages(params)
    model = normalize_model(Map.get(params, "model"))
    mode = parse_mode(Map.get(params, "mode", "default"))
    workspace_path = normalize_workspace_path(Map.get(params, "workspace_path"))
    goal_id = Map.get(params, "goal_id")
    channel_adapter = parse_channel_adapter(Map.get(params, "channel_adapter"))
    channel_id = Map.get(params, "channel_id")

    %__MODULE__{
      messages: messages,
      model: model,
      mode: mode,
      workspace_path: workspace_path,
      goal_id: goal_id,
      channel_adapter: channel_adapter,
      channel_id: channel_id
    }
  end

  @doc """
  Build request for update.
  """
  def build_for_update(session_id, params) do
    title = Map.get(params, "title")
    workspace_path = normalize_workspace_path(Map.get(params, "workspace_path"))

    %__MODULE__{
      session_id: session_id,
      title: title,
      workspace_path: workspace_path
    }
  end

  @doc """
  Build request for search.
  """
  def build_for_search(session_id, params) do
    query = Map.get(params, "q", "")

    %__MODULE__{
      session_id: session_id,
      search_query: query
    }
  end

  @doc """
  Build request for resume.
  """
  def build_for_resume(session_id, params) do
    messages = extract_messages(params)
    model = normalize_model(Map.get(params, "model"))
    mode = parse_mode(Map.get(params, "mode", "default"))
    workspace_path = normalize_workspace_path(Map.get(params, "workspace_path"))

    %__MODULE__{
      session_id: session_id,
      messages: messages,
      model: model,
      mode: mode,
      workspace_path: workspace_path
    }
  end

  @doc """
  Validate request based on type.
  """
  def validate(%__MODULE__{} = request, type) do
    case type do
      :create -> validate_create(request)
      :send_message -> validate_send_message(request)
      :resume -> validate_resume(request)
      :update -> validate_update(request)
      :search -> validate_search(request)
      :delete -> :ok
    end
  end

  @doc """
  Convert to session store options.
  """
  def to_store_opts(%__MODULE__{} = request) do
    base_opts = [messages: request.messages]

    base_opts =
      case request.model do
        model when is_binary(model) -> Keyword.put(base_opts, :requested_model, model)
        _ -> base_opts
      end

    base_opts =
      if request.workspace_path do
        Keyword.put(base_opts, :workspace_path, request.workspace_path)
      else
        base_opts
      end

    metadata = build_metadata(request)

    if map_size(metadata) > 0 do
      Keyword.put(base_opts, :metadata, metadata)
    else
      base_opts
    end
  end

  @doc """
  Convert to runtime options.
  """
  def to_runtime_opts(%__MODULE__{} = request, session_store) do
    [
      session_store: session_store,
      session_id: request.session_id,
      model: request.model,
      mode: "interactive",
      style: request.mode,
      permission_mode: :approval_required,
      run_policy: :always,
      workspace_path: request.workspace_path
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ── Private ─────────────────────────────────────────────────────

  defp extract_messages(params) do
    case Map.get(params, "message") do
      msg when is_binary(msg) and msg != "" ->
        [msg]

      nil ->
        Map.get(params, "messages", [])

      _ ->
        []
    end
  end

  defp normalize_model(model) when is_binary(model) do
    case String.trim(model) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_model(_), do: nil

  defp parse_mode(mode) when is_binary(mode) do
    case mode do
      "default" -> :default
      "simple" -> :simple
      "creative" -> :creative
      "precise" -> :precise
      _ -> :default
    end
  end

  defp parse_mode(_), do: :default

  defp parse_channel_adapter(nil), do: nil
  defp parse_channel_adapter(adapter) when is_atom(adapter), do: adapter

  defp parse_channel_adapter(adapter) when is_binary(adapter) do
    String.to_existing_atom(adapter)
  rescue
    ArgumentError -> nil
  end

  defp normalize_workspace_path(nil), do: nil

  defp normalize_workspace_path(path) when is_binary(path) do
    trimmed = String.trim(path)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_workspace_path(_), do: nil

  defp build_metadata(%__MODULE__{} = request) do
    %{}
    |> put_if_not_nil(:goal_id, request.goal_id)
    |> put_if_not_nil(:channel_adapter, request.channel_adapter)
    |> put_if_not_nil(:channel_id, request.channel_id)
    |> put_if_not_nil(:requested_model, request.model)
  end

  defp put_if_not_nil(map, _key, nil), do: map
  defp put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  # ── Validators ───────────────────────────────────────────────────

  defp validate_create(%__MODULE__{}), do: :ok

  defp validate_send_message(%__MODULE__{messages: messages}) do
    if length(messages) == 0 do
      {:error, :no_messages}
    else
      :ok
    end
  end

  defp validate_resume(%__MODULE__{messages: messages}) do
    if length(messages) == 0 do
      {:error, :no_messages}
    else
      :ok
    end
  end

  defp validate_update(%__MODULE__{title: title, workspace_path: workspace_path}) do
    cond do
      is_binary(title) and String.trim(title) != "" -> :ok
      is_binary(workspace_path) -> :ok
      true -> {:error, :invalid_update}
    end
  end

  defp validate_search(%__MODULE__{search_query: query}) do
    if query == nil or query == "" do
      {:error, :missing_query}
    else
      :ok
    end
  end
end
