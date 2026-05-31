defmodule AIBrain.LLM.ReqLLMStream do
  @moduledoc """
  LLM streaming bridge using ReqLLM.

  Replaces AIBrain.LLM.Client. Handles model resolution, message/tool
  conversion, streaming event emission, and result collection.
  """

  require Logger

  @doc """
  Stream text from an LLM using ReqLLM.

  Args:
    - `model_spec` - string like "anthropic:claude-sonnet-4-6" or LLMDB.Model
    - `messages` - list of message maps `%{role: "...", content: "..."}`
    - `tools` - list of tool maps `%{name: "...", description: "...", input_schema: %{...}}`
    - `opts` - keyword: `:system`, `:model`, `:on_event`, `:temperature`, `:max_tokens`, `:thinking`

  Returns:
    - `{:ok, result}` where result is `%{text: ..., tool_uses: [...], content: [...], stop_reason: :stop | :tool_call | :max_tokens}`
    - `{:error, reason}` on failure
  """
  def stream(model_spec, messages, tools \\ [], opts \\ []) do
    on_event = Keyword.get(opts, :on_event, fn _ -> :ok end)
    caller = self()

    with {:ok, model} <- resolve_model(model_spec),
         {:ok, req_llm_tools} <- convert_tools(tools),
         {:ok, stream_response} <- call_req_llm(model, messages, req_llm_tools, opts) do

      try do
        classify_and_emit(stream_response, on_event, caller)
      after
        stream_response.cancel.()
      end
    else
      {:error, %{status: 429} = _e} ->
        Logger.warning("ReqLLM: rate limited")
        {:error, :rate_limited}

      {:error, %{status: 401} = _e} ->
        {:error, {:provider_error, "API key invalid"}}

      {:error, %{status: 403} = _e} ->
        {:error, {:provider_error, "Access denied, check account balance or permissions"}}

      {:error, %{status: status} = _e} when is_integer(status) and status >= 500 ->
        {:error, {:provider_error, "Server error (HTTP #{status}), retry later"}}

      {:error, %Mint.TransportError{} = e} ->
        {:error, {:provider_error, "Cannot connect to model server: #{Exception.message(e)}"}}

      {:error, %{__struct__: _} = e} when not is_map_key(e, :status) ->
        error_msg =
          if Map.has_key?(e, :reason), do: e.reason, else: Exception.message(e)

        {:error, {:provider_error, "Model call failed: #{error_msg}"}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolve a model spec to an LLMDB.Model.
  """
  def resolve_model(model_spec) when is_binary(model_spec) do
    case ReqLLM.model(model_spec) do
      {:ok, model} -> {:ok, model}
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve_model(%LLMDB.Model{} = model), do: {:ok, model}

  def resolve_model({provider, model_name}) do
    resolve_model("#{provider}:#{model_name}")
  end

  @doc """
  Resolve the default model spec from system settings.
  """
  def default_model_spec do
    case AIBrain.Data.SystemSetting.default_llm_model() do
      {provider_name, model_name} when is_binary(provider_name) and is_binary(model_name) ->
        "#{provider_name}:#{model_name}"

      _ ->
        Application.get_env(:ai_brain, :smart_router, %{})[:strong] || "anthropic:claude-sonnet-4-6"
    end
  end

  @doc """
  Resolve a model spec from a potentially unqualified model name.

  Handles:
  - "provider:model" → pass through
  - nil / "" / "default" → system default
  - "model-name" → auto-detect provider from system settings
  """
  def resolve_model_spec(nil), do: default_model_spec()
  def resolve_model_spec(""), do: default_model_spec()
  def resolve_model_spec("default"), do: default_model_spec()

  def resolve_model_spec(model_name) when is_binary(model_name) do
    if String.contains?(model_name, ":") do
      model_name
    else
      case AIBrain.Data.SystemSetting.default_llm_model() do
        {provider, ^model_name} -> "#{provider}:#{model_name}"
        _ -> default_model_spec()
      end
    end
  end

  # ── Private ────────────────────────────────────────

  defp call_req_llm(model, messages, tools, opts) do
    system = Keyword.get(opts, :system)
    temperature = Keyword.get(opts, :temperature)
    max_tokens = Keyword.get(opts, :max_tokens)
    thinking_budget = Keyword.get(opts, :thinking)

    req_opts = []
    req_opts = if system, do: Keyword.put(req_opts, :system_prompt, system), else: req_opts
    req_opts = if tools != [], do: Keyword.put(req_opts, :tools, tools), else: req_opts
    req_opts = if temperature, do: Keyword.put(req_opts, :temperature, temperature), else: req_opts
    req_opts = if max_tokens, do: Keyword.put(req_opts, :max_tokens, max_tokens), else: req_opts
    req_opts = if thinking_budget, do: Keyword.put(req_opts, :thinking, thinking_budget), else: req_opts
    req_opts = Keyword.put(req_opts, :provider, model.provider)

    ReqLLM.stream_text(model, messages, req_opts)
  end

  defp classify_and_emit(stream_response, on_event, caller) do
    {:ok, text_acc} = Agent.start_link(fn -> "" end)
    {:ok, thinking_acc} = Agent.start_link(fn -> %{} end)

    try do
      {:ok, _response} =
        ReqLLM.StreamResponse.process_stream(stream_response,
          on_result: fn text ->
            Agent.update(text_acc, fn acc -> acc <> text end)
            event = {:text_delta, text}
            on_event.(event)
            send(caller, {:sse_event, event})
          end,
          on_thinking: fn thinking ->
            Agent.update(thinking_acc, fn acc ->
              idx = map_size(acc)
              Map.put(acc, idx, (Map.get(acc, idx, "") || "") <> thinking)
            end)

            idx = Agent.get(thinking_acc, &map_size/1) - 1

            if !Map.has_key?(Agent.get(thinking_acc, fn a -> a end), idx) or
                 Agent.get(thinking_acc, fn a -> Map.get(a, idx) || "" end) == thinking do
              event = {:thinking_start, %{index: idx}}
              on_event.(event)
              send(caller, {:sse_event, event})
            end

            event = {:thinking_delta, %{index: idx, text: thinking}}
            on_event.(event)
            send(caller, {:sse_event, event})
          end,
          on_tool_call: fn chunk ->
            event =
              case chunk.arguments do
                %{} = args when map_size(args) > 0 ->
                  {:tool_use_complete, %{id: chunk.metadata[:id] || chunk.name, name: chunk.name, input: args}}

                _ ->
                  {:tool_use_start, %{index: 0, id: chunk.metadata[:id] || chunk.name, name: chunk.name}}
              end

            on_event.(event)
            send(caller, {:sse_event, event})
          end
        )

      # Get final results
      text = Agent.get(text_acc, fn t -> t end)
      thinking_map = Agent.get(thinking_acc, fn t -> t end)

      classification = ReqLLM.StreamResponse.classify(stream_response)

      content_blocks =
        build_content_blocks(text, thinking_map, classification.tool_calls)

      event = {:stop, classification.finish_reason || :stop}
      on_event.(event)
      send(caller, {:sse_event, event})
      send(caller, {:sse_done})

      {:ok,
       %{
         text: text,
         thinking_bufs: thinking_map,
         tool_uses:
           Enum.map(classification.tool_calls, fn tc ->
             %{
               id: Map.get(tc, :id) || tc.name,
               name: tc.name,
               input: tc.arguments
             }
           end),
         content: content_blocks,
         stop_reason: normalize_stop_reason(classification.finish_reason),
         text_buf: text,
         events: []
       }}
    after
      Agent.stop(text_acc)
      Agent.stop(thinking_acc)
    end
  rescue
    e ->
      Logger.error("ReqLLMStream: stream processing failed: #{Exception.message(e)}")
      {:error, {:stream_error, Exception.message(e)}}
  end

  defp build_content_blocks(text, thinking_map, tool_calls) do
    blocks = []

    blocks =
      if text != "" and text != nil do
        blocks ++ [%{type: "text", text: text}]
      else
        blocks
      end

    blocks =
      Enum.reduce(thinking_map, blocks, fn {_idx, thinking_text}, acc ->
        if thinking_text != "" && thinking_text != nil do
          acc ++ [%{type: "thinking", text: thinking_text}]
        else
          acc
        end
      end)

    blocks =
      Enum.reduce(tool_calls, blocks, fn tc, acc ->
        acc ++ [%{type: "tool_use", id: Map.get(tc, :id) || tc.name, name: tc.name, input: tc.arguments}]
      end)

    blocks
  end

  defp normalize_stop_reason(reason) when reason in ~w(tool_use tool_calls), do: :tool_call
  defp normalize_stop_reason(reason) when reason in ~w(stop end_turn), do: :stop
  defp normalize_stop_reason(reason) when reason in ~w(max_tokens length), do: :max_tokens
  defp normalize_stop_reason(_reason), do: :stop

  defp convert_tools([]), do: {:ok, []}
  defp convert_tools(tools) when is_list(tools) do
    converted =
      Enum.map(tools, fn tool ->
        name = tool[:name] || tool.name || tool["name"]
        description = tool[:description] || tool.description || tool["description"]
        input_schema = tool[:input_schema] || tool.input_schema || tool["input_schema"] || %{}

        params =
          case input_schema do
            %{"properties" => props, "required" => required} when is_map(props) ->
              Enum.map(props, fn {k, v} ->
                param_opts = [type: map_json_type(v["type"]), required: k in (required || [])]
                param_opts = if v["description"], do: Keyword.put(param_opts, :doc, v["description"]), else: param_opts
                param_opts = if v["enum"], do: Keyword.put(param_opts, :in, v["enum"]), else: param_opts
                {String.to_atom(k), param_opts}
              end)

            %{properties: props, required: required} when is_map(props) ->
              Enum.map(props, fn {k, v} ->
                v_type = v[:type] || v["type"]
                param_opts = [type: map_json_type(v_type), required: k in (required || [])]
                v_desc = v[:description] || v["description"]
                param_opts = if v_desc, do: Keyword.put(param_opts, :doc, v_desc), else: param_opts
                {String.to_atom(k), param_opts}
              end)

            _ ->
              []
          end

        [name: name, description: description, parameters: params]
      end)

    {:ok, converted}
  end

  defp map_json_type("string"), do: :string
  defp map_json_type("integer"), do: :integer
  defp map_json_type("number"), do: :float
  defp map_json_type("boolean"), do: :boolean
  defp map_json_type("object"), do: :map
  defp map_json_type("array"), do: {:list, :any}
  defp map_json_type(_), do: :string
end
