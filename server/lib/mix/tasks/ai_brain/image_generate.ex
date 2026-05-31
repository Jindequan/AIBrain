defmodule Mix.Tasks.AiBrain.Image.Generate do
  @moduledoc """
  Generates an image using a configured provider from the Registry.

  ## Usage

      mix ai_brain.image.generate --provider openai 'a sunset over mountains'
      mix ai_brain.image.generate --provider my-replicate 'a cat in a hat' --size 1024x1024

  ## Options

    * `--provider` - Name of the provider in the Registry (required)
    * `--model` - Model identifier (optional, backend-dependent)
    * `--size` - Image size, e.g. "1024x1024" (DALL-E only)
    * `--output` - Path to save the image file (optional)
  """

  use Mix.Task

  @shortdoc "Generate an image using a configured provider"

  def run(args) do
    {parsed, rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          model: :string,
          size: :string,
          output: :string
        ]
      )

    prompt = Enum.join(rest, " ")

    if prompt == "" do
      IO.puts(:stderr, "Usage: mix ai_brain.image.generate --provider <name> 'prompt text'")
      exit({:shutdown, 1})
    end

    provider_name = Keyword.get(parsed, :provider)

    unless provider_name do
      IO.puts(:stderr, "Error: --provider is required")
      IO.puts(:stderr, "Usage: mix ai_brain.image.generate --provider <name> 'prompt text'")
      exit({:shutdown, 1})
    end

    # Start the application to ensure Registry is available
    Mix.Task.run("app.start")

    opts =
      []
      |> Keyword.put(:model, parsed[:model])
      |> Keyword.put(:size, parsed[:size])

    case AIBrain.Provider.Registry.get(provider_name) do
      {:ok, provider} ->
        IO.puts("Generating image with provider '#{provider_name}'...")
        IO.puts("Prompt: #{prompt}")
        IO.puts("")

        case AIBrain.Provider.Types.Image.generate(provider, prompt, opts) do
          {:ok, image_data} ->
            handle_result(image_data, parsed[:output])

          {:error, reason} ->
            IO.puts(:stderr, "Error: #{reason}")
            exit({:shutdown, 1})
        end

      {:error, :not_found} ->
        IO.puts(:stderr, "Error: Provider '#{provider_name}' not found in Registry")
        exit({:shutdown, 1})
    end
  end

  defp handle_result(image_data, nil) do
    if String.starts_with?(image_data, "http://") or String.starts_with?(image_data, "https://") do
      IO.puts("Image URL: #{image_data}")
    else
      output_path =
        Path.join(System.tmp_dir!(), "ai_brain_image_#{System.system_time(:microsecond)}.png")

      File.write!(output_path, Base.decode64!(image_data))
      IO.puts("Image saved to: #{output_path}")
    end
  end

  defp handle_result(image_data, output_path) do
    if String.starts_with?(image_data, "http://") or String.starts_with?(image_data, "https://") do
      IO.puts("Image URL: #{image_data}")
      IO.puts("Note: --output path ignored for URL results. Download manually.")
    else
      File.write!(output_path, Base.decode64!(image_data))
      IO.puts("Image saved to: #{output_path}")
    end
  end
end
