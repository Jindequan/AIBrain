defmodule AIBrain.Tool.Builtin.Image do
  @behaviour AIBrain.Tool.Behaviour

  require Logger

  @moduledoc """
  Image generation tool — wraps AIBrain.Provider.Types.Image.generate/3.

  The LLM can call this to generate images from text prompts.
  Auto-detects an image-capable provider from the Registry.
  """

  @impl true
  def name, do: "image_generate"

  @impl true
  def description do
    "Generate an image from a text prompt. Supports DALL-E (OpenAI) and Replicate backends. " <>
      "Returns the generated image URL or file path."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "prompt" => %{
          "type" => "string",
          "description" => "Text prompt describing the image to generate"
        },
        "size" => %{
          "type" => "string",
          "enum" => ["1024x1024", "1792x1024", "1024x1792"],
          "description" => "Image size (DALL-E only, default: 1024x1024)"
        },
        "provider" => %{
          "type" => "string",
          "description" => "Provider name in Registry (optional, auto-detected if omitted)"
        }
      },
      "required" => ["prompt"]
    }
  end

  @impl true
  def read_only?, do: false

  @impl true
  def risk_category, do: :network

  @impl true
  def execute(%{"prompt" => prompt} = args, _context) do
    opts = if size = args["size"], do: [size: size], else: []

    case find_provider(args["provider"]) do
      {:ok, provider} ->
        case AIBrain.Provider.Types.Image.generate(provider, prompt, opts) do
          {:ok, result} ->
            format_result(result)

          {:error, reason} ->
            {:error, "Image generation failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(%{}, _context) do
    {:error, "Missing required parameter: prompt"}
  end

  defp find_provider(nil) do
    try do
      providers = AIBrain.Provider.Registry.all_providers(AIBrain.Provider.Registry)

      image_provider =
        Enum.find(providers, fn p ->
          endpoints = if is_map(p), do: Map.get(p, :endpoints, %{}) || %{}, else: %{}

          Map.has_key?(endpoints, "openai") or
            Map.has_key?(endpoints, "image") or
            Map.has_key?(endpoints, "replicate")
        end)

      if image_provider do
        {:ok, image_provider}
      else
        {:error,
         "No image generation provider configured. Add one via Settings → Providers (OpenAI or Replicate)."}
      end
    rescue
      e ->
        Logger.warning("Image provider auto-detection failed: #{Exception.message(e)}")

        {:error,
         "No image generation provider configured. Add one via Settings → Providers (OpenAI or Replicate)."}
    end
  end

  defp find_provider(name) do
    case AIBrain.Provider.Registry.get(AIBrain.Provider.Registry, name) do
      {:ok, provider} -> {:ok, provider}
      {:error, :not_found} -> {:error, "Provider '#{name}' not found in Registry"}
    end
  end

  defp format_result(result) when is_binary(result) do
    cond do
      String.starts_with?(result, "http") ->
        {:ok, %{"url" => result, "format" => "url"}}

      String.starts_with?(result, "/") or String.starts_with?(result, ".") ->
        {:ok, %{"path" => result, "format" => "file"}}

      true ->
        {:ok, %{"base64" => String.slice(result, 0, 100) <> "...", "format" => "base64"}}
    end
  end
end
