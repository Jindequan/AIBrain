defmodule AIBrain.LLM.Adapters.Protocol.OpenAI do
  @moduledoc """
  OpenAI-compatible API protocol adapter.

  Converts internal %Message{} structs to OpenAI API format and parses
  OpenAI SSE responses into internal event tuples.
  """

  require Logger

  @default_max_tokens 8096

  # ── Public API ────────────────────────────────────────────────────────

  def url_path, do: "/v1/chat/completions"

  def headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end

  def build_body(provider, messages, tools, opts) do
    api_messages =
      messages
      |> Enum.map(&convert_message/1)

    all_messages =
      case opts[:system] do
        nil -> api_messages
        "" -> api_messages
        sys -> [%{role: "system", content: sys} | api_messages]
      end

    model = resolve_model(provider, opts[:model])

    %{
      "model" => model,
      "max_tokens" => opts[:max_tokens] || @default_max_tokens,
      "stream" => true,
      "messages" => all_messages,
      "tools" => to_openai_tools(tools)
    }
  end

  def parse_sse_line("data: [DONE]"), do: :skip

  def parse_sse_line("data: " <> json) do
    case Jason.decode(json) do
      {:ok, decoded} -> classify_events(decoded)
      _ -> :skip
    end
  end

  def parse_sse_line("data:" <> json) do
    case Jason.decode(json) do
      {:ok, decoded} -> classify_events(decoded)
      _ -> :skip
    end
  end

  def parse_sse_line(_line), do: :skip

  # ── Expand consolidated messages ─────────────────────────────────────────

  @doc """
  Expand consolidated assistant messages (with embedded tool results from storage)
  back into the proper API sequence: assistant + separate tool messages.
  Skips expansion if the next message is already a tool message (active session).
  """
  def expand_consolidated_messages(messages) do
    result =
      messages
      |> Enum.with_index()
      |> Enum.flat_map(fn {msg, idx} ->
        # Normalize string-keyed maps from JSON storage to atom keys
        msg = normalize_msg_keys(msg)

        with %{role: "assistant", content: content} <- msg,
             true <- has_embedded_results?(content),
             true <- needs_expansion?(messages, idx) do
          expanded = expand_assistant(msg, content)

          Logger.warning(
            "EXPAND: msg[#{idx}] role=#{msg.role} -> #{length(expanded)} msgs (#{length(expanded) - 1} tool msgs)"
          )

          expanded
        else
          false ->
            Logger.warning(
              "NOEXPAND: msg[#{idx}] role=#{Map.get(msg, :role)} has_embedded?=#{has_embedded_results?(Map.get(msg, :content, []))}"
            )

            [msg]

          _ ->
            [msg]
        end
      end)

    Logger.warning("EXPANDED total: #{length(messages)} -> #{length(result)} messages")
    result
  end

  defp is_tool_use_block(block) do
    Map.get(block, :type) == "tool_use" or Map.get(block, "type") == "tool_use"
  end

  defp has_embedded_results?(content) when is_list(content) do
    Enum.any?(content, fn block ->
      is_tool_use_block(block) and
        (Map.has_key?(block, :output) or Map.has_key?(block, "output") or
           Map.has_key?(block, :status) or Map.has_key?(block, "status"))
    end)
  end

  defp has_embedded_results?(_), do: false

  defp needs_expansion?(messages, idx) do
    case Enum.at(messages, idx + 1) do
      nil -> true
      %{role: "tool"} -> false
      _ -> true
    end
  end

  defp expand_assistant(msg, content) do
    tool_uses = Enum.filter(content, &is_tool_use_block/1)

    clean_content =
      Enum.map(content, fn block ->
        if is_tool_use_block(block) do
          Map.drop(block, [:output, "output", :status, "status", :is_error, "is_error"])
        else
          block
        end
      end)

    clean_assistant = Map.put(msg, :content, clean_content)

    tool_msgs =
      Enum.map(tool_uses, fn tu ->
        %{
          role: "tool",
          content: [
            %{
              type: "tool_result",
              tool_use_id: tu[:id] || tu["id"] || "",
              content: tu[:output] || tu["output"] || ""
            }
          ]
        }
      end)

    [clean_assistant | tool_msgs]
  end

  # ── Message conversion ────────────────────────────────────────────────

  def convert_message(%{role: role} = message) when not is_map_key(message, :content) do
    convert_message(%{role: role, content: ""})
  end

  def convert_message(%{role: role, content: content}) do
    blocks = normalize_msg_content(content)
    role = normalize_role(role, blocks)

    case role do
      "tool" ->
        tool_result = find_block(blocks, "tool_result")
        c = tool_result[:content] || tool_result["content"] || ""

        %{
          role: "tool",
          tool_call_id: tool_result[:tool_use_id] || tool_result["tool_use_id"],
          content: if(is_binary(c), do: c, else: safe_json(c))
        }

      "user" ->
        images = Enum.filter(blocks, &(Map.get(&1, :type) == "image_url"))

        cond do
          # Only text: flatten to string (backward-compatible)
          images == [] ->
            text = find_block(blocks, "text")
            %{role: "user", content: text[:text] || text["text"] || ""}

          # Has images: pass full content array through, resolving local file URLs
          true ->
            converted =
              blocks
              |> Enum.map(fn
                %{type: "image_url"} = img -> resolve_local_image(img)
                %{"type" => "image_url"} = img -> resolve_local_image(img)
                %{type: "text", text: t} -> %{type: "text", text: t}
                %{"type" => "text", "text" => t} -> %{type: "text", text: t}
                _other -> %{type: "text", text: ""}
              end)

            %{role: "user", content: converted}
        end

      "assistant" ->
        text = find_block(blocks, "text")

        tool_uses =
          Enum.filter(
            blocks,
            &(Map.get(&1, :type) == "tool_use" || Map.get(&1, "type") == "tool_use")
          )

        base = %{role: "assistant", content: text[:text] || text["text"] || ""}

        if tool_uses != [] do
          tc =
            Enum.map(tool_uses, fn tu ->
              id = tu[:id] || tu["id"]
              name = tu[:name] || tu["name"]
              input = tu[:input] || tu["input"] || %{}

              %{
                id: id,
                type: "function",
                function: %{name: name, arguments: Jason.encode!(input)}
              }
            end)

          Map.put(base, :tool_calls, tc)
        else
          base
        end

      "system" ->
        text = find_block(blocks, "text")
        %{role: "system", content: text[:text] || text["text"] || ""}

      role ->
        %{role: role, content: ""}
    end
  end

  # Catch-all: normalize string-keyed maps from JSON storage
  def convert_message(%{"role" => role} = message) when not is_map_key(message, "content") do
    convert_message(%{role: role, content: ""})
  end

  def convert_message(%{"role" => role, "content" => content}) do
    convert_message(%{role: role, content: normalize_msg_keys(content)})
  end

  def convert_assistant(blocks) do
    text = find_block(blocks, "text")

    tool_uses =
      Enum.filter(
        blocks,
        &(Map.get(&1, :type) == "tool_use" || Map.get(&1, "type") == "tool_use")
      )

    base = %{role: "assistant", content: text[:text] || text["text"] || nil}

    if tool_uses != [] do
      tc =
        Enum.map(tool_uses, fn tu ->
          id = tu[:id] || tu["id"]
          name = tu[:name] || tu["name"]
          input = tu[:input] || tu["input"] || %{}

          %{
            id: id,
            type: "function",
            function: %{name: name, arguments: Jason.encode!(input)}
          }
        end)

      Map.put(base, :tool_calls, tc)
    else
      base
    end
  end

  # ── SSE parsing ───────────────────────────────────────────────────────

  defp classify_events(%{"choices" => choices}) do
    choice = List.first(choices) || %{}
    delta = choice["delta"] || %{}
    finish_reason = choice["finish_reason"]

    events =
      []
      |> add_text(delta)
      |> add_tool_calls(delta)
      |> add_finish(finish_reason)

    if events == [], do: :skip, else: events
  end

  defp classify_events(%{"error" => error}) do
    [{:sse_error, error}]
  end

  defp classify_events(_event), do: :skip

  defp add_text(events, %{"content" => content}) when is_binary(content) and content != "" do
    events ++ [{:text_delta, content}]
  end

  defp add_text(events, _delta), do: events

  defp add_tool_calls(events, %{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    Enum.reduce(tool_calls, events, fn tc, acc ->
      index = tc["index"]
      acc = add_tool_start(acc, tc, index)
      add_tool_args(acc, tc, index)
    end)
  end

  defp add_tool_calls(events, _delta), do: events

  defp add_tool_start(events, %{"id" => id} = tc, index) when is_binary(id) and id != "" do
    name = get_in(tc, ["function", "name"]) || ""
    events ++ [{:tool_use_start, %{index: index, id: id, name: name}}]
  end

  defp add_tool_start(events, _tc, _index), do: events

  defp add_tool_args(events, tc, index) do
    case get_in(tc, ["function", "arguments"]) do
      args when is_binary(args) and args != "" ->
        events ++ [{:tool_input_delta, %{index: index, chunk: args}}]

      _ ->
        events
    end
  end

  defp add_finish(events, reason) when is_binary(reason) and reason != "",
    do: events ++ [{:stop, reason}]

  defp add_finish(events, _reason), do: events

  # ── Internal helpers ──────────────────────────────────────────────────

  defp to_openai_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "function" => %{
          "name" => tool["name"],
          "description" => tool["description"],
          "parameters" => tool["input_schema"]
        }
      }
    end)
  end

  defp resolve_model(provider, requested_model) do
    AIBrain.Provider.Info.map_model(provider, requested_model || "default")
  end

  defp normalize_role("user", blocks) do
    case find_block(blocks, "tool_result") do
      block when map_size(block) > 0 -> "tool"
      _ -> "user"
    end
  end

  defp normalize_role(role, _blocks), do: role

  defp normalize_msg_content(content) when is_binary(content) and content != "",
    do: [%{type: "text", text: content}]

  defp normalize_msg_content(content) when is_binary(content), do: []
  defp normalize_msg_content(content), do: content

  defp find_block(blocks, type) do
    Enum.find(blocks, %{}, fn block ->
      Map.get(block, :type) == type || Map.get(block, "type") == type
    end)
  end

  # Recursively convert string-keyed maps from JSON storage to atom-keyed maps.
  # Structs pass through as-is (they already have atom keys and may not implement Enumerable).
  defp normalize_msg_keys(msg) when is_struct(msg), do: msg

  defp normalize_msg_keys(msg) when is_map(msg) do
    if Map.has_key?(msg, :role) or Map.has_key?(msg, :type) do
      # Already atom-keyed — recurse into known value fields
      Map.new(msg, fn
        {:content, content} -> {:content, normalize_msg_keys(content)}
        {:input, input} -> {:input, normalize_msg_keys(input)}
        {:output, output} -> {:output, normalize_msg_keys(output)}
        {:metadata, meta} -> {:metadata, normalize_msg_keys(meta)}
        pair -> pair
      end)
    else
      # String-keyed — convert known keys to atoms, recurse into nested values
      Map.new(msg, fn
        {"content", content} -> {:content, normalize_msg_keys(content)}
        {"input", input} -> {:input, normalize_msg_keys(input)}
        {"output", output} -> {:output, normalize_msg_keys(output)}
        {"metadata", meta} -> {:metadata, normalize_msg_keys(meta)}
        {k, v} -> {string_to_known_atom(k), v}
      end)
    end
  end

  defp normalize_msg_keys(list) when is_list(list), do: Enum.map(list, &normalize_msg_keys/1)
  defp normalize_msg_keys(other), do: other

  defp string_to_known_atom("id"), do: :id
  defp string_to_known_atom("role"), do: :role
  defp string_to_known_atom("content"), do: :content
  defp string_to_known_atom("name"), do: :name
  defp string_to_known_atom("type"), do: :type
  defp string_to_known_atom("text"), do: :text
  defp string_to_known_atom("input"), do: :input
  defp string_to_known_atom("output"), do: :output
  defp string_to_known_atom("status"), do: :status
  defp string_to_known_atom("is_error"), do: :is_error
  defp string_to_known_atom("metadata"), do: :metadata
  defp string_to_known_atom("tool_use_id"), do: :tool_use_id
  defp string_to_known_atom("thinking_index"), do: :thinking_index
  defp string_to_known_atom(k), do: k

  defp safe_json(value) do
    Jason.encode!(value)
  rescue
    _ -> inspect(value)
  end

  # Resolve image_url blocks that reference local file uploads (/api/v1/files/:id)
  # to inline base64 data URLs so the LLM API can access them.
  defp resolve_local_image(block) do
    url =
      Map.get(block, :image_url, %{}) |> Map.get(:url) ||
        Map.get(block, "image_url", %{}) |> Map.get("url")

    case url do
      "/api/v1/files/" <> id ->
        safe_id = Path.basename(id)
        upload_dir = Path.join(System.user_home!(), ".aibrain/uploads")

        case find_upload(upload_dir, safe_id) do
          {:ok, path, content_type} ->
            case File.read(path) do
              {:ok, data} ->
                b64 = Base.encode64(data)
                %{type: "image_url", image_url: %{url: "data:#{content_type};base64,#{b64}"}}

              {:error, _} ->
                block
            end

          :error ->
            block
        end

      _ ->
        # External URL, data URL, or nil — pass through as-is
        block
    end
  end

  defp find_upload(dir, id) do
    case File.ls(dir) do
      {:ok, files} ->
        case Enum.find(files, &String.starts_with?(&1, id)) do
          nil ->
            :error

          name ->
            path = Path.join(dir, name)
            content_type = infer_content_type(name)
            {:ok, path, content_type}
        end

      {:error, _} ->
        :error
    end
  end

  defp infer_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".bmp" -> "image/bmp"
      _ -> "application/octet-stream"
    end
  end
end
