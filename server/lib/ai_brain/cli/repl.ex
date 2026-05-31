defmodule AIBrain.CLI.REPL do
  @moduledoc """
  Terminal REPL for chatting with AIBrain.

  Start via: `mix run -e 'AIBrain.CLI.REPL.start()'` or in iex: `AIBrain.CLI.REPL.start()`

  Commands:
    /exit, /quit  — exit the REPL
    /help         — show help
    /memory       — show memory stats
    /clear        — start a new session
    /health       — show system health
    /sessions     — list recent sessions
    /resume <id>  — resume a past session
    /workspace    — show current workspace
  """

  require Logger

  @prompt "You> "
  @ai_prefix "\nAI> "
  @history_file Path.join(System.user_home!(), ".aibrain/cli_history.txt")

  def start(opts \\ []) do
    ensure_application_started()
    session_id = Keyword.get(opts, :session_id, "cli-#{System.unique_integer([:positive])}")
    cmd_history = load_cmd_history()

    IO.puts("\n#{IO.ANSI.bright()}#{IO.ANSI.cyan()}AIBrain CLI#{IO.ANSI.reset()}")
    IO.puts("Type /help for commands, /exit to quit.\n")

    loop(session_id, [], cmd_history)
  end

  defp loop(session_id, history, cmd_history) do
    input = IO.gets(@prompt)

    case input do
      :eof ->
        exit_cleanly(session_id, cmd_history)

      nil ->
        exit_cleanly(session_id, cmd_history)

      line ->
        line = String.trim(line)

        cond do
          line == "" ->
            loop(session_id, history, cmd_history)

          String.starts_with?(line, "/") ->
            handle_command(line, session_id, history, cmd_history)

          true ->
            handle_message(line, session_id, history, cmd_history)
        end
    end
  end

  # ── Command handlers ──────────────────────────────────────────────

  defp handle_command("/exit", session_id, _history, cmd_history),
    do: exit_cleanly(session_id, cmd_history)

  defp handle_command("/quit", session_id, _history, cmd_history),
    do: exit_cleanly(session_id, cmd_history)

  defp handle_command("/help", session_id, history, cmd_history) do
    IO.puts("""

    #{IO.ANSI.bright()}Commands:#{IO.ANSI.reset()}
      /exit, /quit  Exit
      /help         This help
      /memory       Show memory store stats
      /clear        Start a new session
      /health       Show system health
      /sessions     List recent sessions
      /resume <id>  Resume a past session
      /workspace    Show current workspace

    #{IO.ANSI.bright()}Tips:#{IO.ANSI.reset()}
      End a line with \\\\ to continue on the next line
      Ctrl+C to interrupt, Ctrl+D to exit
      Run in iex for readline support: `iex -S mix` then `AIBrain.CLI.REPL.start()`
    """)

    loop(session_id, history, cmd_history)
  end

  defp handle_command("/memory", session_id, history, cmd_history) do
    try do
      total = AIBrain.Memory.Manager.total_entries()
      IO.puts("Memory entries: #{total} across 4 stores")
    rescue
      _ -> IO.puts("Memory manager unavailable")
    end

    loop(session_id, history, cmd_history)
  end

  defp handle_command("/clear", _old_session_id, _history, cmd_history) do
    new_id = "cli-#{System.unique_integer([:positive])}"
    IO.puts("New session: #{new_id}")
    loop(new_id, [], cmd_history)
  end

  defp handle_command("/health", session_id, history, cmd_history) do
    try do
      snap = AIBrain.System.HealthAggregator.snapshot()
      status_str = snap.system_status |> to_string() |> String.upcase()
      IO.puts("System: #{status_str} | Uptime: #{format_uptime(snap.uptime_seconds)}")
      IO.puts("DB: #{snap.db}")

      IO.puts(
        "LLM calls (1h): #{snap.telemetry[:llm_calls] || 0} | Errors: #{snap.telemetry[:llm_errors] || 0}"
      )
    rescue
      _ -> IO.puts("Health check unavailable")
    end

    loop(session_id, history, cmd_history)
  end

  defp handle_command("/sessions", session_id, history, cmd_history) do
    store = AIBrain.Config.session_store()

    try do
      sessions = store.list_sessions(store)

      if sessions == [] do
        IO.puts("No sessions found.")
      else
        IO.puts("\n#{IO.ANSI.bright()}Recent sessions:#{IO.ANSI.reset()}")

        sessions
        |> Enum.sort_by(&(&1[:updated_at] || &1["updated_at"] || ""), :desc)
        |> Enum.take(15)
        |> Enum.each(fn s ->
          sid = s[:session_id] || s["session_id"]
          title = s[:title] || s["title"] || "Untitled"
          status = s[:status] || s["status"]

          IO.puts(
            "  #{String.slice(sid, 0, 20)}  #{String.pad_trailing(to_string(status), 10)}  #{title}"
          )
        end)
      end
    rescue
      _ -> IO.puts("Unable to list sessions.")
    end

    loop(session_id, history, cmd_history)
  end

  defp handle_command("/resume " <> target_id, session_id, history, cmd_history) do
    target = String.trim(target_id)
    store = AIBrain.Config.session_store()

    case store.load_session(store, target) do
      {:ok, session} when is_map(session) ->
        IO.puts("Resumed session: #{target}")
        IO.puts("Title: #{session[:title] || "(untitled)"}")
        IO.puts("Messages: #{length(session.messages)}")
        loop(target, session.messages, cmd_history)

      _ ->
        IO.puts("Session not found: #{target}")
        loop(session_id, history, cmd_history)
    end
  end

  defp handle_command("/workspace", session_id, history, cmd_history) do
    ws = Application.get_env(:ai_brain, :workspace_path, System.user_home!())
    IO.puts("Workspace: #{ws}")
    loop(session_id, history, cmd_history)
  end

  defp handle_command(cmd, session_id, history, cmd_history) do
    IO.puts("Unknown command: #{cmd}. Type /help for commands.")
    loop(session_id, history, cmd_history)
  end

  # ── Message handler ───────────────────────────────────────────────

  defp handle_message(input, session_id, history, cmd_history) do
    messages = history ++ [AIBrain.Message.new("user", content: input)]
    cmd_history = [input | cmd_history] |> Enum.take(500)

    IO.write(@ai_prefix)

    result =
      AIBrain.AgentRuntime.Orchestrator.run_messages(
        messages,
        [
          session_id: session_id,
          session_store: AIBrain.Session.Store.Memory,
          on_event: &handle_stream_event(&1),
          trigger_source: "cli"
        ],
        %{source_type: "manual"}
      )

    case result do
      {:ok, _text, new_history} ->
        # final newline after streaming
        IO.puts("")
        loop(session_id, new_history, cmd_history)

      {:error, reason, _detail} ->
        IO.puts("\n#{IO.ANSI.red()}Error: #{format_error(reason)}#{IO.ANSI.reset()}")
        loop(session_id, history, cmd_history)
    end
  end

  # ── Stream event handling ─────────────────────────────────────────

  defp handle_stream_event({:text_delta, text}) do
    IO.write(text)
  end

  defp handle_stream_event(%{type: :tool_use_start_sse} = event) do
    IO.puts("")
    IO.puts("#{IO.ANSI.yellow()}[tool: #{event.tool_name}]#{IO.ANSI.reset()}")
  end

  defp handle_stream_event(%{type: :tool_result} = event) do
    case event[:result] do
      {:ok, output} when is_binary(output) ->
        preview = String.slice(output, 0, 200) |> String.replace("\n", " ")

        IO.puts(
          "#{IO.ANSI.green()}  => #{preview}#{if byte_size(output) > 200, do: "...", else: ""}#{IO.ANSI.reset()}"
        )

      {:error, reason} ->
        IO.puts("#{IO.ANSI.red()}  => error: #{reason}#{IO.ANSI.reset()}")

      _ ->
        :ok
    end

    IO.write("\n#{@ai_prefix}")
  end

  defp handle_stream_event(%{type: :tool_timeout} = event) do
    IO.puts("#{IO.ANSI.red()}  [timeout: #{event.tool_name}]#{IO.ANSI.reset()}")
    IO.write(@ai_prefix)
  end

  defp handle_stream_event(%{type: :tool_crashed} = event) do
    IO.puts("#{IO.ANSI.red()}  [crashed: #{event.tool_name} - #{event.reason}]#{IO.ANSI.reset()}")
    IO.write(@ai_prefix)
  end

  defp handle_stream_event(_), do: :ok

  # ── Helpers ───────────────────────────────────────────────────────

  defp ensure_application_started do
    unless Process.whereis(AIBrain.Supervisor) do
      IO.puts("Starting AIBrain...")
      {:ok, _} = Application.ensure_all_started(:ai_brain)
    end
  end

  defp exit_cleanly(_session_id, cmd_history) do
    save_cmd_history(cmd_history)
    IO.puts("\nGoodbye.")
  end

  # ── Command History Persistence ─────────────────────────────────

  defp load_cmd_history do
    case File.read(@history_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.take(500)

      _ ->
        []
    end
  end

  defp save_cmd_history(history) do
    File.mkdir_p!(Path.dirname(@history_file))
    content = history |> Enum.reverse() |> Enum.take(500) |> Enum.join("\n")
    File.write(@history_file, content)
  end

  defp format_uptime(seconds) do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)
    "#{hours}h #{minutes}m"
  end

  defp format_error(:max_turns_exceeded), do: "Maximum conversation turns exceeded"
  defp format_error(:max_retries_exceeded), do: "Maximum retries exceeded"
  defp format_error({:provider_error, reason}), do: "Provider error: #{reason}"
  defp format_error(reason), do: inspect(reason)
end
