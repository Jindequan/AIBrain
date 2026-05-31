defmodule AIBrain.Channel.Request do
  @moduledoc """
  Normalizes inbound channel payloads into a stable internal request shape.
  """

  def normalize(request) when is_map(request) do
    schema_version = read_integer(request, :schema_version)
    query_kind = read_atom(request, :query_kind)
    directive_kind = read_atom(request, :directive_kind)
    type = read_atom(request, :type)
    channel = read_atom(request, :channel)
    diagnostic_type = read_atom(request, :diagnostic_type)
    session_id = read_value(request, :session_id)
    content = read_value(request, :content)
    export = read_value(request, :export)
    payload = read_value(request, :payload)

    case {schema_version, query_kind, directive_kind, type, normalized_message(content)} do
      {1, nil, :text_command, _, _} ->
        directive_payload = payload_map(payload)
        command = read_value(directive_payload, :command)

        case normalized_message(command) do
          :capability_status ->
            {:ok,
             compact(%{
               type: :capability_status,
               schema_version: 1,
               directive_kind: :text_command,
               original_type: :directive,
               channel: channel,
               session_id: read_value(directive_payload, :session_id),
               export: read_value(directive_payload, :export),
               content: command
             })}

          _ ->
            {:error, :unsupported_request}
        end

      {1, :capability_status, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :capability_status,
           query_kind: :capability_status,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export),
           content: read_value(query_payload, :content)
         })}

      {1, :diagnostics_summary, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :diagnostics_summary,
           query_kind: :diagnostics_summary,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export)
         })}

      {1, :capability_rejections, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :capability_rejections,
           query_kind: :capability_rejections,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export)
         })}

      {1, :permission_diagnostics_summary, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :permission_diagnostics_summary,
           query_kind: :permission_diagnostics_summary,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export)
         })}

      {1, :sandbox_diagnostics_summary, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :sandbox_diagnostics_summary,
           query_kind: :sandbox_diagnostics_summary,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export)
         })}

      {1, :sandbox_feedback_entries, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :sandbox_feedback_entries,
           query_kind: :sandbox_feedback_entries,
           schema_version: 1,
           channel: channel,
           session_id: read_value(query_payload, :session_id),
           export: read_value(query_payload, :export)
         })}

      {1, :operator_diagnostic, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :operator_diagnostic,
           query_kind: :operator_diagnostic,
           schema_version: 1,
           channel: channel,
           diagnostic_type: read_atom(query_payload, :diagnostic_type),
           payload: read_value(query_payload, :payload)
         })}

      {1, :scheduler_status, _, _, _} ->
        {:ok,
         compact(%{
           type: :scheduler_status,
           query_kind: :scheduler_status,
           schema_version: 1,
           channel: channel
         })}

      {1, :task_status, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :task_status,
           query_kind: :task_status,
           schema_version: 1,
           channel: channel,
           task_id: read_value(query_payload, :task_id)
         })}

      {1, :task_list, _, _, _} ->
        {:ok,
         compact(%{
           type: :task_list,
           query_kind: :task_list,
           schema_version: 1,
           channel: channel
         })}

      {1, :task_output, _, _, _} ->
        query_payload = payload_map(payload)

        {:ok,
         compact(%{
           type: :task_output,
           query_kind: :task_output,
           schema_version: 1,
           channel: channel,
           task_id: read_value(query_payload, :task_id)
         })}

      {version, query_kind, directive_kind, _, _}
      when not is_nil(version) and (not is_nil(query_kind) or not is_nil(directive_kind)) ->
        {:error, :unsupported_request}

      {_, _, _, :sandbox_feedback, _} ->
        {:ok,
         compact(%{
           type: :operator_diagnostic,
           diagnostic_type: :sandbox_feedback,
           payload: request,
           channel: channel,
           original_type: :sandbox_feedback
         })}

      {_, _, _, :permission_checked, _} ->
        case read_atom(request, :decision) do
          :denied ->
            {:ok,
             compact(%{
               type: :operator_diagnostic,
               diagnostic_type: :permission_denial,
               payload: request,
               channel: channel,
               original_type: :permission_checked
             })}

          _ ->
            {:error, :unsupported_request}
        end

      {_, _, _, :operator_diagnostic, _} ->
        {:ok,
         compact(%{
           type: :operator_diagnostic,
           diagnostic_type: diagnostic_type,
           payload: payload,
           channel: channel
         })}

      {_, _, _, :capability_status, _} ->
        {:ok,
         compact(%{
           type: :capability_status,
           channel: channel,
           session_id: session_id,
           content: content,
           export: export
         })}

      {_, _, _, :message, :capability_status} ->
        {:ok,
         compact(%{
           type: :capability_status,
           original_type: :message,
           channel: channel,
           session_id: session_id,
           content: content,
           export: export
         })}

      _ ->
        {:error, :unsupported_request}
    end
  end

  def normalize(_request), do: {:error, :unsupported_request}

  defp normalized_message(content) when is_binary(content) do
    case String.trim(content) do
      "/capabilities" -> :capability_status
      "capabilities" -> :capability_status
      _ -> :unsupported
    end
  end

  defp normalized_message(_content), do: :unsupported

  defp read_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp read_integer(map, key) do
    case read_value(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp read_atom(map, key) do
    case read_value(map, key) do
      value when is_atom(value) ->
        value

      value when is_binary(value) ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> nil
        end

      _ ->
        nil
    end
  end

  defp payload_map(payload) when is_map(payload), do: payload
  defp payload_map(_payload), do: %{}

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
