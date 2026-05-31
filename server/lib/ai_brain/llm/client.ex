defmodule AIBrain.LLM.Client do
  require Logger
  alias AIBrain.Provider.Info

  @default_model Application.compile_env(:ai_brain, :default_model, "default")

  def default_model, do: @default_model

  def resolve_model(provider, requested_model \\ nil) do
    Info.map_model(provider, requested_model || @default_model)
  end

  def resolve_model_for_scene(provider, scene) when is_atom(scene) do
    Info.get_model_for_scene(provider, scene) || resolve_model(provider)
  end

  def stream(provider, messages, tools, opts \\ []) do
    AIBrain.Telemetry.Metrics.span(
      [:llm, :call],
      %{
        provider: provider.name,
        model: opts[:model] || "default",
        protocol: opts[:protocol] || "openai"
      },
      fn ->
        do_stream(provider, messages, tools, opts)
      end
    )
  end

  defp do_stream(provider, messages, tools, opts) do
    protocol = opts[:protocol] || "openai"
    adapter = adapter_for(provider, protocol)
    ep = Info.get_endpoint(provider, protocol)

    if is_nil(ep) do
      Logger.error("Provider #{provider.name} has no endpoint for protocol #{protocol}")
      {:error, :transport, :no_endpoint}
    else
      url = Map.get(ep, :url) || ep.base_url <> adapter.url_path()

      {http_client, req_opts} = Keyword.pop(opts, :http_client, AIBrain.LLM.HTTP)
      {on_event, req_opts} = Keyword.pop(req_opts, :on_event, fn _event -> :ok end)
      # Expand consolidated messages before sending to any adapter
      expanded = AIBrain.LLM.Adapters.Protocol.OpenAI.expand_consolidated_messages(messages)
      body = adapter.build_body(provider, expanded, tools, req_opts)

      msg_roles =
        Enum.map(body["messages"] || [], fn m -> Map.get(m, :role) || Map.get(m, "role") end)

      Logger.debug(
        "API BODY: #{length(expanded)} expanded msgs, roles=#{inspect(Enum.map(expanded, & &1.role))}"
      )

      Logger.debug("API BODY messages roles: #{inspect(msg_roles)}")
      # Log message sequence structure for debugging tool_call validation
      # Note: Only log role sequence, not full messages (which may contain structs)
      seq_str = build_sequence_summary(body["messages"] || [])
      Logger.debug("API message sequence: #{seq_str}")
      headers = adapter.headers(ep.api_key)
      caller = self()

      # Use a closure-based state container instead of process dictionary
      # to avoid race conditions in concurrent requests
      {:ok, state_agent} = Agent.start_link(fn -> %{sse_error: nil, raw_body: ""} end)
      # Cap raw_body accumulation to 10 MB to prevent unbounded memory growth
      max_raw_body_size = 10 * 1024 * 1024

      try do
        result =
          http_client.post(url,
            headers: headers,
            json: body,
            into: fn {:data, chunk}, {req, resp} ->
              # Accumulate raw body for HTTP error diagnostics (capped at max_raw_body_size)
              Agent.update(state_agent, fn state ->
                if byte_size(state.raw_body) < max_raw_body_size do
                  %{state | raw_body: state.raw_body <> chunk}
                else
                  state
                end
              end)

              chunk
              |> String.split("\n")
              |> Enum.each(fn line ->
                case adapter.parse_sse_line(line) do
                  :skip ->
                    :ok

                  {:sse_error, error_data} ->
                    Logger.error("LLM SSE error: #{inspect(error_data)}")
                    Agent.update(state_agent, fn state -> %{state | sse_error: error_data} end)
                    on_event.({:error, error_data})
                    send(caller, {:sse_event, {:error, error_data}})
                    send(caller, {:sse_done})

                  events when is_list(events) ->
                    Enum.each(events, fn event ->
                      on_event.(event)
                      send(caller, {:sse_event, event})
                    end)

                  event ->
                    on_event.(event)
                    send(caller, {:sse_event, event})
                end
              end)

              {:cont, {req, resp}}
            end,
            receive_timeout: Application.get_env(:ai_brain, :llm_timeout, 30_000)
          )

        # Get final state before shutting down agent
        final_state = Agent.get(state_agent, & &1)

        case result do
          {:error, %Req.TransportError{reason: :timeout} = exception} ->
            Logger.error("LLM transport timeout: #{inspect(exception)}")
            {:error, :transport, :timeout}

          {:error, exception} ->
            Logger.error("LLM transport error: #{inspect(exception)}")
            {:error, :transport, exception}

          {:ok, %Req.Response{status: status, headers: headers, body: resp_body}}
          when status >= 400 ->
            raw_body = if final_state.raw_body == "", do: resp_body, else: final_state.raw_body
            Logger.error("LLM HTTP error #{status}: #{inspect(raw_body)}")
            {:error, :http, status, headers, raw_body}

          {:ok, %Req.Response{status: status} = response} ->
            Logger.info("LLM stream completed with status #{status}")

            if final_state.sse_error do
              Logger.error("LLM provider SSE error, returning as sse_error tuple")
              {:error, :sse_error, final_state.sse_error}
            else
              if status != 200 do
                Logger.warning(
                  "Unexpected LLM response status #{status}: #{inspect(response.body)}"
                )
              end

              send(caller, {:sse_done})
              {:ok, :streaming_complete}
            end
        end
      after
        Agent.stop(state_agent)
      end
    end
  end

  # Build a compact sequence summary for debugging API validation issues
  defp build_sequence_summary(messages) do
    Enum.reduce(messages, {[], 0}, fn msg, {acc, idx} ->
      role = Map.get(msg, :role) || Map.get(msg, "role") || "unknown"
      tool_calls = Map.get(msg, :tool_calls) || Map.get(msg, "tool_calls")
      tool_call_id = Map.get(msg, :tool_call_id) || Map.get(msg, "tool_call_id")

      summary =
        cond do
          role == "assistant" and is_list(tool_calls) and tool_calls != [] ->
            ids = Enum.map(tool_calls, fn tc -> Map.get(tc, :id) || Map.get(tc, "id") || "?" end)
            "assistant[tc:#{length(tool_calls)} ids=#{inspect(ids)}]"

          role == "tool" and is_binary(tool_call_id) ->
            "tool[tc_id=#{tool_call_id}]"

          true ->
            role
        end

      {acc ++ ["[#{idx}]#{summary}"], idx + 1}
    end)
    |> elem(0)
    |> Enum.join(" -> ")
  end

  # Dispatch to provider-specific adapter first, fall back to protocol adapter
  defp adapter_for(%{name: name}, _protocol)
       when name in ~w(Deepseek deepseek deep_seek DeepSeek), do: AIBrain.LLM.Adapters.Deepseek

  defp adapter_for(%{name: name}, _protocol) when name in ~w(Bailian bailian 百炼 百炼免费模型),
    do: AIBrain.LLM.Adapters.Bailian

  defp adapter_for(_provider, _protocol), do: AIBrain.LLM.Adapters.Protocol.OpenAI
end
