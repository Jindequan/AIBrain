defmodule AIBrain.Audio.Config do
  @moduledoc """
  Persistent TTS/STT configuration stored in ~/.aibrain/tts_config.json.
  """

  @config_file "tts_config.json"

  @defaults %{
    tts_enabled: true,
    auto_reply: false,
    voice: "default",
    language: "en-US",
    speed: 1.0
  }

  # ── Public API ──

  @spec get() :: map()
  def get do
    data = read_config()
    Map.merge(@defaults, Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end))
  rescue
    _ -> @defaults
  end

  @spec get(atom()) :: term()
  def get(key) when is_atom(key) do
    Map.get(get(), key)
  end

  @spec update(map()) :: :ok
  def update(new_values) when is_map(new_values) do
    current = read_config()
    updated = Map.merge(current, Map.new(new_values, fn {k, v} -> {to_string(k), v} end))
    write_config(updated)
    :ok
  end

  @doc "Available voices. On macOS, always lists say voices; shows Piper voices if configured."
  def voices do
    # macOS `say` voices are always available regardless of which backend is active
    say_voices = list_say_voices()

    # Piper voices if configured
    piper_voices =
      if AIBrain.Audio.TTS.backend_available?(:piper) and default_piper_model() do
        [
          %{
            name: "piper-default",
            language: "en-US",
            description: "Piper TTS (high quality)",
            backend: "piper"
          }
        ]
      else
        []
      end

    say_voices ++ piper_voices
  end

  defp list_say_voices do
    if AIBrain.Audio.TTS.backend_available?(:say) do
      case System.cmd("say", ["-v", "?"], stderr_to_stdout: true) do
        {output, 0} ->
          output
          |> String.split("\n")
          |> Enum.filter(&(&1 != ""))
          |> Enum.map(fn line ->
            case String.split(line, ~r/\s{2,}/, parts: 2) do
              [name, rest] ->
                lang =
                  case String.split(rest) do
                    [lang | _] when byte_size(lang) == 5 -> lang
                    _ -> "unknown"
                  end

                %{
                  name: String.trim(name),
                  language: lang,
                  description: String.trim(rest),
                  backend: "say"
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    else
      []
    end
  end

  defp default_piper_model do
    Application.get_env(:ai_brain, :tts_piper_model)
  end

  @doc "List supported languages."
  def languages do
    voices()
    |> Enum.map(& &1.language)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ── Persistence ──

  defp config_path do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join(data_dir, @config_file)
  end

  defp read_config do
    path = config_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, data} -> data
            _ -> %{}
          end

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp write_config(data) do
    path = config_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(data, pretty: true))
  end
end
