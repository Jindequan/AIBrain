defmodule AIBrain.Web.Handlers.STTHandler do
  import Plug.Conn
  require Logger

  alias AIBrain.Audio.STT

  # ── Transcription ─────────────────────────────────
  # Electron: saves file locally, sends path
  # Browser: sends base64 audio data

  def handle_transcribe(conn, params) do
    cond do
      # ── Electron mode: path provided ──
      Map.has_key?(params, "path") ->
        audio_path = params["path"]

        cond do
          audio_path == "" ->
            json(conn, 400, %{error: "No audio path provided", code: "missing_audio_path"})

          not File.exists?(audio_path) ->
            json(conn, 400, %{error: "Audio file not found", code: "audio_file_not_found"})

          File.stat!(audio_path).size > max_path_audio_bytes() ->
            json(conn, 413, %{error: "Audio file too large", code: "audio_file_too_large"})

          File.stat!(audio_path).size < min_audio_bytes() ->
            json(conn, 400, %{
              error: "Audio file too small",
              code: "audio_file_too_small"
            })

          not STT.available?() ->
            json(conn, 503, %{
              error: "Speech-to-text is not available",
              code: "stt_unavailable"
            })

          true ->
            transcribe(conn, audio_path, params)
        end

      # ── Browser mode: base64 audio provided ──
      Map.has_key?(params, "audio") ->
        audio_b64 = params["audio"]

        cond do
          audio_b64 == "" ->
            json(conn, 400, %{error: "No audio data provided", code: "missing_audio_data"})

          byte_size(audio_b64) > max_base64_audio_bytes() ->
            json(conn, 413, %{error: "Audio data too large", code: "audio_data_too_large"})

          not STT.available?() ->
            json(conn, 503, %{
              error: "Speech-to-text is not available",
              code: "stt_unavailable"
            })

          true ->
            transcribe_from_base64(conn, audio_b64, params)
        end

      true ->
        json(conn, 400, %{error: "Missing audio input", code: "missing_audio_input"})
    end
  end

  defp transcribe(conn, audio_path, params) do
    opts = [model: Map.get(params, "model", "base")]

    opts =
      if lang = Map.get(params, "language"), do: Keyword.put(opts, :language, lang), else: opts

    case STT.transcribe(audio_path, opts) do
      {:ok, text} ->
        json(conn, 200, %{text: text})

      {:error, reason} ->
        Logger.error("STT transcription failed: #{inspect(reason)}")
        json(conn, 500, %{error: "Transcription failed", code: "transcription_failed"})
    end
  rescue
    e ->
      Logger.error("STT transcription error: #{Exception.message(e)}")
      json(conn, 500, %{error: "Transcription failed", code: "transcription_failed"})
  end

  defp transcribe_from_base64(conn, audio_b64, params) do
    audio_data =
      case Base.decode64(audio_b64) do
        {:ok, data} -> data
        _ -> audio_b64
      end

    if byte_size(audio_data) < min_audio_bytes() do
      json(conn, 400, %{error: "Audio data too small", code: "audio_data_too_small"})
    else
      tmp_dir = System.tmp_dir!()
      input_path = Path.join(tmp_dir, "stt_input_#{System.system_time(:millisecond)}.webm")

      try do
        File.write!(input_path, audio_data)

        opts = [model: Map.get(params, "model", "base")]

        opts =
          if lang = Map.get(params, "language"),
            do: Keyword.put(opts, :language, lang),
            else: opts

        case STT.transcribe(input_path, opts) do
          {:ok, text} ->
            json(conn, 200, %{text: text})

          {:error, reason} ->
            Logger.error("STT transcription failed: #{inspect(reason)}")
            json(conn, 500, %{error: "Transcription failed", code: "transcription_failed"})
        end
      rescue
        e ->
          Logger.error("STT transcription error: #{Exception.message(e)}")
          json(conn, 500, %{error: "Transcription failed", code: "transcription_failed"})
      after
        File.rm(input_path)
      end
    end
  end

  # ── Status ───────────────────────────────────────

  def handle_status(conn) do
    json(conn, 200, %{available: STT.available?()})
  end

  # ── Model management ─────────────────────────────

  def handle_list_models(conn) do
    models = STT.list_models()
    json(conn, 200, %{models: models})
  end

  def handle_download_model(conn, name) do
    case STT.download_model(name) do
      {:ok, :already_installed} ->
        json(conn, 200, %{status: "already_installed"})

      {:ok, :downloaded} ->
        json(conn, 200, %{status: "downloaded"})

      {:error, reason} ->
        Logger.error("STT model download failed for #{name}: #{inspect(reason)}")
        json(conn, 500, %{error: "Model download failed", code: "model_download_failed"})
    end
  end

  def handle_delete_model(conn, name) do
    case STT.remove_model(name) do
      {:ok, :removed} ->
        json(conn, 200, %{status: "removed"})

      {:error, :not_found} ->
        json(conn, 404, %{error: "Model not found"})
    end
  end

  # ── JSON helper ──────────────────────────────────

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp max_path_audio_bytes do
    Application.get_env(:ai_brain, :stt_max_path_audio_bytes, 50_000_000)
  end

  defp max_base64_audio_bytes do
    Application.get_env(:ai_brain, :stt_max_base64_audio_bytes, 8_000_000)
  end

  defp min_audio_bytes do
    Application.get_env(:ai_brain, :stt_min_audio_bytes, 100)
  end
end
