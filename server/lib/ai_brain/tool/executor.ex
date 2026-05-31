defmodule AIBrain.Tool.Executor do
  use GenServer
  require Logger
  alias AIBrain.Tool.{Registry, Error, Result}

  @inline_limit 10_000

  def start_link(opts) do
    registry = Keyword.fetch!(opts, :registry)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, %{registry: registry, executor_map: %{}}, name: name)
  end

  def run(server, tool_uses, context) do
    timeout = context[:timeout] || 300_000
    GenServer.call(server, {:run, tool_uses, context}, timeout)
  end

  def registry(server) do
    GenServer.call(server, :registry, 10_000)
  end

  def reload(server \\ __MODULE__) do
    GenServer.call(server, :reload, 10_000)
  end

  def init(%{registry: reg} = state) do
    executor_map = build_builtin_map(reg)
    Logger.info("Tool.Executor: loaded #{map_size(executor_map)} tools")
    {:ok, Map.put(state, :executor_map, executor_map)}
  end

  def handle_call({:run, tool_uses, context}, _from, %{executor_map: executor_map} = state) do
    {reads, writes} =
      Enum.split_with(tool_uses, fn %{name: name} ->
        Registry.read_only?(state.registry, name)
      end)

    read_results = run_parallel(reads, executor_map, context)
    write_results = run_serial(writes, executor_map, context)

    {:reply, read_results ++ write_results, state}
  end

  def handle_call(:registry, _from, %{registry: reg} = state) do
    {:reply, reg, state}
  end

  def handle_call(:reload, _from, %{registry: reg} = state) do
    executor_map = build_builtin_map(reg)
    Logger.info("Tool.Executor: reloaded executor_map with #{map_size(executor_map)} tools")
    {:reply, :ok, Map.put(state, :executor_map, executor_map)}
  end

  defp run_parallel([], _executor_map, _ctx), do: []

  defp run_parallel(tool_uses, executor_map, ctx) do
    timeout = ctx[:timeout] || 300_000

    tool_uses
    |> Task.async_stream(
      fn %{id: id, name: name, input: input} ->
        {id, execute_one(executor_map, name, input, Map.put(ctx, :tool_use_id, id))}
      end,
      max_concurrency: 10,
      timeout: timeout
    )
    |> Enum.zip(tool_uses)
    |> Enum.map(fn
      {{:ok, result}, _original} ->
        result

      {{:exit, reason}, original} ->
        {original.id, {:error, Error.execution("Task exited: #{inspect(reason)}")}}
    end)
  end

  defp run_serial(tool_uses, executor_map, ctx) do
    Enum.map(tool_uses, fn %{id: id, name: name, input: input} ->
      {id, execute_one(executor_map, name, input, Map.put(ctx, :tool_use_id, id))}
    end)
  end

  defp execute_one(executor_map, name, input, ctx) do
    AIBrain.Telemetry.Metrics.span([:tool, :execute], %{tool_name: name}, fn ->
      case Map.get(executor_map, name) do
        nil ->
          {:error, Error.from("Unknown tool: #{name}")}

        {mod, _is_skill} ->
          result = do_execute(mod, name, input, ctx)
          wrap_result(result, mod, name, ctx)
      end
    end)
  end

  defp do_execute(mod, _name, input, ctx) when is_atom(mod) do
    try do
      mod.execute(input, ctx)
    rescue
      e -> {:error, Error.execution(Exception.message(e))}
    catch
      :exit, reason -> {:error, Error.execution("Tool exited: #{inspect(reason)}")}
      :throw, reason -> {:error, Error.execution("Tool threw: #{inspect(reason)}")}
    end
  end

  defp do_execute({handler_spec, :external}, name, input, ctx) do
    case AIBrain.Tool.ExternalRunner.run(handler_spec, input, ctx) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, Error.external_service("#{name}: #{reason}")}
    end
  end

  defp wrap_result({:ok, output}, mod, name, ctx) do
    {content, tool_meta} = extract_structured(output, name)
    size = byte_size(content)

    if size > @inline_limit do
      summary = tool_summarize(mod, content, name)
      file_path = write_to_store(content, ctx)

      {:ok,
       %Result{
         content: filter_injection(summary, name),
         file_path: file_path,
         truncated: true,
         byte_size: size,
         metadata: tool_meta
       }}
    else
      {:ok,
       %Result{
         content: filter_injection(content, name),
         byte_size: size,
         metadata: tool_meta
       }}
    end
  end

  defp wrap_result({:error, %Error{} = err}, _mod, _name, _ctx) do
    {:error, err}
  end

  defp wrap_result({:error, reason}, _mod, _name, _ctx) do
    {:error, Error.from(reason)}
  end

  defp extract_structured(%{content: content} = map, name) when is_binary(content) do
    meta = Map.get(map, :metadata) || Map.get(map, "metadata") || %{}
    meta = normalize_meta(meta)

    tool_keys =
      ~w(path lines encoding results_count query source exit_code command cwd url total_lines returned_lines has_more next_offset)a

    top_extra =
      map |> Map.drop([:content, :metadata, "content", "metadata"]) |> Map.take(tool_keys)

    meta_extra = Map.take(meta, tool_keys)

    {content,
     Map.merge(
       %{"tool_name" => name},
       Map.merge(meta, Map.merge(normalize_meta(top_extra), meta_extra))
     )}
  end

  defp extract_structured(map, name) when is_map(map) and map != %{} do
    content = stringify(map)
    meta = Map.drop(normalize_meta(map), ["content", "metadata"])
    {content, Map.put(meta, "tool_name", name)}
  end

  defp extract_structured(output, name) when is_binary(output) do
    content = stringify(output)
    {content, %{"tool_name" => name}}
  end

  defp extract_structured(output, name) do
    content = stringify(output)
    {content, %{"tool_name" => name}}
  end

  defp normalize_meta(meta) when is_map(meta) do
    Map.new(meta, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_meta(_), do: %{}

  defp tool_summarize(mod, output, name) do
    if function_exported?(mod, :summarize, 2) do
      mod.summarize(output, [])
    else
      generic_summarize(output, name)
    end
  end

  defp generic_summarize(output, name) do
    lines = String.split(output, "\n")
    total = length(lines)

    case Result.head_tail(lines) do
      {:full, all} ->
        "[#{name}] #{total} lines\n#{Enum.join(all, "\n")}\n[Full output saved to file]"

      {:split, head, tail, skipped} ->
        error_count = Enum.count(lines, &error_line?/1)

        stats =
          "[#{name}] #{total} lines, #{skipped} omitted" <>
            if error_count > 0, do: ", #{error_count} error/warning lines", else: ""

        "#{stats}\n--- HEAD ---\n#{Enum.join(head, "\n")}\n" <>
          "--- ... #{skipped} lines omitted ... ---\n" <>
          "--- TAIL ---\n#{Enum.join(tail, "\n")}\n[Full output saved to file]"
    end
  end

  defp error_line?(line) do
    l = String.downcase(line)

    String.contains?(l, "error") or String.contains?(l, "warning") or
      String.contains?(l, "failed") or String.contains?(l, "fatal")
  end

  defp write_to_store(output, ctx) do
    case ctx[:file_store] do
      nil ->
        nil

      store ->
        tool_use_id = ctx[:tool_use_id] || "unknown"
        path = Path.join([store, "tool_outputs", "#{tool_use_id}.txt"])
        dir = Path.dirname(path)

        with :ok <- File.mkdir_p(dir),
             :ok <- File.write(path, output) do
          path
        else
          {:error, reason} ->
            Logger.warning("Tool.Executor: failed to write output to #{path}: #{inspect(reason)}")
            nil
        end
    end
  end

  defp build_builtin_map(tool_registry) do
    Registry.all(tool_registry)
    |> Enum.map(fn mod -> {mod.name(), {mod, false}} end)
    |> Map.new()
  end

  defp stringify(o) when is_binary(o), do: o
  defp stringify(o) when is_map(o), do: Jason.encode!(o)
  defp stringify(o) when is_list(o), do: Enum.map_join(o, "\n", &stringify/1)
  defp stringify(o), do: inspect(o)

  defp filter_injection(text, tool_name) do
    case AIBrain.Tool.Sandbox.InjectionFilter.filter(tool_name || "unknown", text) do
      {:clean, filtered} -> filtered
      {:injected, filtered} -> filtered
      {:truncated, filtered} -> filtered
    end
  end
end
