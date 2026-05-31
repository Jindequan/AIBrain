defmodule AIBrain.Provider.Types.Image do
  @moduledoc """
  Behaviour for image generation providers.

  Each backend module implements `generate/3` to produce an image from a text prompt.
  """

  alias AIBrain.Provider.Info

  @doc """
  Generates an image from a text prompt using the given provider.

  ## Options

    * `:model` — model name/version (default depends on backend)
    * `:size` — image size (e.g. "1024x1024", only for DALL-E)
    * `:n` — number of images to generate (default 1)

  Returns `{:ok, image_data}` where image_data is a base64-encoded string or URL,
  or `{:error, reason}`.
  """
  @callback generate(provider :: Info.t(), prompt :: String.t(), opts :: Keyword.t()) ::
              {:ok, String.t()} | {:error, String.t()}

  @doc """
  Generates an image by dispatching to the appropriate backend based on the provider's endpoints.
  """
  @spec generate(provider :: Info.t(), prompt :: String.t(), opts :: Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate(provider, prompt, opts \\ []) do
    backend = resolve_backend(provider)

    case backend do
      {:ok, mod} -> mod.generate(provider, prompt, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the name of the image generation backend module to use for the given provider.
  """
  @spec resolve_backend(Info.t()) :: {:ok, module()} | {:error, String.t()}
  def resolve_backend(%Info{name: name}) do
    cond do
      String.contains?(name, "openai") or String.contains?(name, "dall-e") ->
        {:ok, AIBrain.Provider.Types.Image.OpenAI}

      String.contains?(name, "replicate") ->
        {:ok, AIBrain.Provider.Types.Image.Replicate}

      true ->
        {:error, "No supported image generation backend found for provider: #{name}"}
    end
  end

  def resolve_backend(_), do: {:error, "Invalid provider"}
end
