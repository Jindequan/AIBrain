defmodule AIBrain.Web.Handlers.TTSHandler do
  import Plug.Conn

  alias AIBrain.Audio.Config

  def handle_get_config(conn) do
    config = Config.get()

    json(conn, 200, %{
      config: %{
        tts_enabled: config.tts_enabled,
        auto_reply: config.auto_reply,
        voice: config.voice,
        language: config.language,
        speed: config.speed
      }
    })
  end

  def handle_update_config(conn, params) do
    allowed = ~w(tts_enabled auto_reply voice language speed)

    normalized =
      params
      |> Map.take(allowed)
      |> Enum.map(fn {k, v} ->
        {k,
         case v do
           "true" -> true
           "false" -> false
           other when is_binary(other) -> other
           other -> other
         end}
      end)
      |> Map.new()

    Config.update(normalized)
    config = Config.get()

    json(conn, 200, %{
      config: %{
        tts_enabled: config.tts_enabled,
        auto_reply: config.auto_reply,
        voice: config.voice,
        language: config.language,
        speed: config.speed
      },
      message: "TTS config updated"
    })
  end

  def handle_voices(conn) do
    voices = Config.voices()
    json(conn, 200, %{voices: voices, backend: AIBrain.Audio.TTS.detect_backend() |> to_string()})
  end

  def handle_languages(conn) do
    languages = Config.languages()
    json(conn, 200, %{languages: languages})
  end

  def handle_synthesize(conn, params) do
    text = Map.get(params, "text", "")

    if text == "" do
      json(conn, 400, %{error: "text parameter is required"})
    else
      config = Config.get()

      opts = [
        voice: Map.get(params, "voice", config.voice),
        backend: AIBrain.Audio.TTS.detect_backend()
      ]

      case AIBrain.Audio.TTS.synthesize(text, nil, opts) do
        {:ok, path} ->
          # Read the WAV file and serve it
          case File.read(path) do
            {:ok, audio_data} ->
              conn
              |> put_resp_content_type("audio/wav")
              |> put_resp_header("content-disposition", "inline; filename=\"tts.wav\"")
              |> send_resp(200, audio_data)

            {:error, reason} ->
              json(conn, 500, %{error: "Failed to read audio: #{reason}"})
          end

        {:error, reason} ->
          json(conn, 500, %{error: "TTS synthesis failed: #{inspect(reason)}"})
      end
    end
  end

  def handle_get_audio(conn, filename) do
    # Sanitize filename to prevent path traversal
    safe_name = Path.basename(filename)

    if String.match?(safe_name, ~r/^tts_\d+\.wav$/) do
      tmp_dir = System.tmp_dir!()
      path = Path.join(tmp_dir, safe_name)

      case File.read(path) do
        {:ok, audio_data} ->
          conn
          |> put_resp_content_type("audio/wav")
          |> put_resp_header("content-disposition", "inline")
          |> send_resp(200, audio_data)

        {:error, _} ->
          json(conn, 404, %{error: "Audio not found"})
      end
    else
      json(conn, 400, %{error: "Invalid audio filename"})
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
