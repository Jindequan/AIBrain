defmodule AIBrain.Tool.Builtin.TTS do
  @behaviour AIBrain.Tool.Behaviour

  @impl true
  def name, do: "tts"

  @impl true
  def description,
    do: "Convert text to speech audio. Uses best available backend (macOS say, espeak, or Piper)."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "text" => %{"type" => "string", "description" => "Text to convert to speech"},
        "voice" => %{
          "type" => "string",
          "description" => "Voice name (optional, backend-dependent)"
        },
        "output_path" => %{
          "type" => "string",
          "description" => "Output file path (optional, defaults to temp file)"
        }
      },
      "required" => ["text"]
    }
  end

  @impl true
  def read_only?, do: true

  @impl true
  def risk_category, do: :read_only

  @impl true
  def execute(%{"text" => text} = args, _context) do
    if AIBrain.Audio.TTS.available?() do
      opts = [
        voice: Map.get(args, "voice", "default"),
        backend: AIBrain.Audio.TTS.detect_backend()
      ]

      output_path = Map.get(args, "output_path")

      case AIBrain.Audio.TTS.synthesize(text, output_path, opts) do
        {:ok, path} ->
          {:ok,
           %{
             "audio_path" => path,
             "format" => "wav",
             "backend" => AIBrain.Audio.TTS.detect_backend() |> to_string(),
             "text_length" => String.length(text),
             "file_size" => File.stat!(path).size
           }}

        {:error, reason} ->
          {:error, "TTS failed: #{reason}"}
      end
    else
      {:error,
       "No TTS backend available. Install espeak on Linux, or Piper for high-quality TTS."}
    end
  end

  def execute(%{} = args, _context) do
    {:error, "Missing required parameter: text. Got: #{inspect(args)}"}
  end
end
