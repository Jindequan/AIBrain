defmodule AIBrain.Audio.STT do
  @moduledoc """
  Speech-to-text using OpenAI Whisper (free, runs locally).

  Requires `ffmpeg` and `openai-whisper`:
      pip install openai-whisper
  """

  @whisper_args ["-m", "whisper"]

  @model_sizes %{
    "tiny" => 75,
    "tiny.en" => 75,
    "base" => 150,
    "base.en" => 150,
    "small" => 500,
    "small.en" => 500,
    "medium" => 1500,
    "medium.en" => 1500,
    "large" => 3100,
    "large-v3-turbo" => 1600,
    "turbo" => 1600
  }

  @cached_key :ai_brain_stt_python

  @doc "Find the python3 binary that has whisper installed."
  def python_binary do
    case :persistent_term.get(@cached_key, :not_set) do
      :not_set ->
        path = detect_python_binary()
        :persistent_term.put(@cached_key, path)
        path

      path ->
        path
    end
  end

  defp detect_python_binary do
    candidates = ["python3.12", "python3.11", "python3"]

    Enum.find_value(candidates, "python3", fn bin ->
      home = System.user_home!()

      paths =
        [
          Path.join([home, ".asdf", "shims", bin]),
          Path.join("/opt/homebrew/bin", bin),
          Path.join("/usr/local/bin", bin),
          System.find_executable(bin) || bin
        ]
        |> Enum.uniq()

      Enum.find_value(paths, fn path ->
        case System.cmd(path, ["-c", "import whisper"], stderr_to_stdout: true) do
          {_, 0} -> path
          _ -> nil
        end
      end)
    end)
  end

  @doc "List all available Whisper models with their install status."
  def list_models do
    cache_dir = model_cache_dir()

    Enum.map(@model_sizes, fn {name, size_mb} ->
      %{
        name: name,
        size_mb: size_mb,
        installed: File.exists?(Path.join(cache_dir, "#{name}.pt"))
      }
    end)
  end

  @doc "Download (or ensure cached) a Whisper model by name."
  def download_model(name) do
    if model_cached?(name) do
      {:ok, :already_installed}
    else
      dir = model_cache_dir()
      File.mkdir_p!(dir)

      case System.cmd(
             python_binary(),
             [
               "-c",
               "import whisper; whisper.load_model(#{inspect(name)}, download_root=#{inspect(dir)})"
             ],
             stderr_to_stdout: true,
             parallelism: true
           ) do
        {_output, 0} ->
          if model_cached?(name) do
            {:ok, :downloaded}
          else
            {:error, "model file not found after download"}
          end

        {output, _code} ->
          {:error, "Download failed: #{String.trim(output)}"}
      end
    end
  end

  @doc "Remove a downloaded model from cache."
  def remove_model(name) do
    path = model_path(name)

    if File.exists?(path) do
      File.rm!(path)
      {:ok, :removed}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Transcribe an audio file to text.

  ## Options
    * `:model` — model name (default: "base")
    * `:language` — language code, nil for auto-detect
  """
  def transcribe(audio_path, opts \\ []) do
    model = Keyword.get(opts, :model, "base")
    language = Keyword.get(opts, :language)
    tmp_dir = System.tmp_dir!()

    input_name =
      audio_path
      |> Path.basename()
      |> Path.rootname()

    model_dir = model_cache_dir()

    args =
      if language do
        @whisper_args ++
          [
            "--language",
            language,
            audio_path,
            "--model",
            model,
            "--model_dir",
            model_dir,
            "--output_format",
            "txt",
            "--output_dir",
            tmp_dir,
            "--fp16",
            "False"
          ]
      else
        @whisper_args ++
          [
            audio_path,
            "--model",
            model,
            "--model_dir",
            model_dir,
            "--output_format",
            "txt",
            "--output_dir",
            tmp_dir,
            "--fp16",
            "False"
          ]
      end

    case System.cmd(python_binary(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        txt_path = Path.join(tmp_dir, "#{input_name}.txt")

        case File.read(txt_path) do
          {:ok, text} ->
            cleaned = text |> String.trim() |> String.replace(~r/\s+/, " ")
            {:ok, cleaned}

          {:error, _} ->
            alt = Path.join(tmp_dir, "#{input_name}.txt")

            case File.read(alt) do
              {:ok, text} -> {:ok, text |> String.trim() |> String.replace(~r/\s+/, " ")}
              {:error, reason} -> {:error, "Could not read whisper output: #{reason}"}
            end
        end

      {output, _exit_code} ->
        {:error, "Whisper failed: #{String.trim(output)}"}
    end
  end

  @doc "Check if whisper is available via python3 -m whisper."
  def available? do
    case System.cmd(python_binary(), @whisper_args ++ ["--help"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp model_cache_dir do
    Path.join(System.user_home!(), ".aibrain/whisper_models")
  end

  defp model_path(name) do
    Path.join(model_cache_dir(), "#{name}.pt")
  end

  defp model_cached?(name) do
    File.exists?(model_path(name))
  end
end
