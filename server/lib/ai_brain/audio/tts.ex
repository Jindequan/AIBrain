defmodule AIBrain.Audio.TTS do
  @moduledoc """
  Text-to-speech with zero-dependency core and optional enhanced backends.

  ## Backends (auto-detected, best available wins)

    * `:piper`      — Piper TTS (high quality, requires `pip install piper-tts` + a voice model)
    * `:say`        — macOS built-in `say` command
    * `:espeak`     — Linux `espeak` (requires `apt install espeak`)
    * `:none`       — no TTS backend available
  """

  @backends [:say, :piper, :espeak]

  @doc "Synthesize text to a WAV file. Returns `{:ok, output_path}` or `{:error, reason}`."
  def synthesize(text, output_path \\ nil, opts \\ []) do
    backend = Keyword.get(opts, :backend, detect_backend())
    path = output_path || default_output_path()
    voice = Keyword.get(opts, :voice, "default")

    case backend do
      :piper ->
        do_piper(text, path, opts)

      :say ->
        do_say(text, path, voice)

      :espeak ->
        do_espeak(text, path, opts)

      :none ->
        {:error, "No TTS backend available. Install Piper (`pip install piper-tts`) or espeak."}
    end
  end

  @doc "List available voices for the configured backend."
  def voices(backend \\ nil) do
    case backend || detect_backend() do
      :say -> say_voices()
      :espeak -> espeak_voices()
      _ -> []
    end
  end

  @doc "Detect the best available TTS backend."
  def detect_backend do
    Enum.find(@backends, :none, &backend_available?/1)
  end

  @doc "Check if any TTS backend is available."
  def available?, do: detect_backend() != :none

  @doc "Check if a specific backend is available."
  def backend_available?(backend)

  def backend_available?(:piper) do
    System.find_executable("piper") != nil
  end

  def backend_available?(:say) do
    System.find_executable("say") != nil
  end

  def backend_available?(:espeak) do
    System.find_executable("espeak") != nil
  end

  def backend_available?(_), do: false

  # ── macOS `say` backend ──────────────────────────────────────

  defp do_say(text, output_path, voice) do
    args =
      case voice do
        "default" -> ["-o", output_path, "--data-format=LEI16@22050", text]
        v -> ["-v", v, "-o", output_path, "--data-format=LEI16@22050", text]
      end

    case System.cmd("say", args, stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, output_path}

      {error, _} ->
        {:error, "say failed: #{String.trim(error)}"}
    end
  end

  defp say_voices do
    case System.cmd("say", ["-v", "?"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.map(fn line ->
          case String.split(line, ~r/\s{2,}/, parts: 2) do
            [name, rest] ->
              %{name: String.trim(name), lang: extract_lang(rest), description: String.trim(rest)}

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # ── Linux `espeak` backend ────────────────────────────────────

  defp do_espeak(text, output_path, _opts) do
    case System.cmd("espeak", ["-w", output_path, text], stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, output_path}

      {error, _} ->
        {:error, "espeak failed: #{String.trim(error)}"}
    end
  end

  defp espeak_voices do
    case System.cmd("espeak", ["--voices"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.drop(1)

      _ ->
        []
    end
  end

  # ── Piper backend (optional) ──────────────────────────────────

  defp do_piper(text, output_path, opts) do
    model = Keyword.get(opts, :model, default_piper_model())

    if model == nil do
      {:error,
       "Piper model not configured. Set :tts_piper_model in config or pass `model:` option"}
    else
      case System.cmd(
             "piper",
             ["--model", model, "--output_file", output_path],
             stdin: text,
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:ok, output_path}

        {error, _} ->
          {:error, "Piper failed: #{String.trim(error)}"}
      end
    end
  end

  defp default_piper_model do
    Application.get_env(:ai_brain, :tts_piper_model)
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp default_output_path do
    tmp = System.tmp_dir!()
    Path.join(tmp, "tts_#{System.system_time(:millisecond)}.wav")
  end

  defp extract_lang(rest) do
    case String.split(rest) do
      [lang | _] when byte_size(lang) == 5 -> lang
      _ -> "unknown"
    end
  end
end
