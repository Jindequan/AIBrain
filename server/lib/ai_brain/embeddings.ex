defmodule AIBrain.Embeddings do
  @moduledoc """
  Text embedding generation and similarity search.

  Uses an OpenAI-compatible embedding API. Configurable via application config:

      config :ai_brain, AIBrain.Embeddings,
        endpoint: "http://localhost:11434/api/embed",
        model: "nomic-embed-text",
        dimensions: 768,
        api_key: nil  # not needed for Ollama

  Falls back to nil (no embeddings) if the endpoint is not configured.
  """

  require Logger

  @doc "Generate an embedding vector for the given text."
  def embed(text) when is_binary(text) and text != "" do
    case configured_endpoint() do
      nil -> {:error, :not_configured}
      endpoint -> do_embed(endpoint, configured_model(), text)
    end
  end

  def embed(_), do: {:error, :empty_text}

  @doc """
  Compute cosine similarity between two vectors.
  Returns a float between 0 and 1.
  """
  def cosine_similarity(a, b) when is_list(a) and is_list(b) do
    if length(a) != length(b) do
      Logger.warning(
        "Embeddings.cosine_similarity: vector length mismatch (#{length(a)} vs #{length(b)})"
      )

      0.0
    else
      {dot, norm_a, norm_b} =
        Enum.zip(a, b)
        |> Enum.reduce({0.0, 0.0, 0.0}, fn {x, y}, {dot, na, nb} ->
          {dot + x * y, na + x * x, nb + y * y}
        end)

      denom = :math.sqrt(norm_a) * :math.sqrt(norm_b)
      if denom == 0.0, do: 0.0, else: dot / denom
    end
  end

  @doc "Decode a binary BLOB into a list of floats (32-bit LE)."
  def decode_blob(blob) when is_binary(blob) do
    for <<float::float-32-little <- blob>>, do: float
  end

  def decode_blob(_), do: []

  @doc "Encode a list of floats into a binary BLOB (32-bit LE)."
  def encode_blob(vector) when is_list(vector) do
    for f <- vector, into: <<>>, do: <<f::float-32-little>>
  end

  defp configured_endpoint do
    Application.get_env(:ai_brain, AIBrain.Embeddings, [])[:endpoint] ||
      Application.get_env(:ai_brain, :embedding_endpoint)
  end

  defp configured_model do
    Application.get_env(:ai_brain, AIBrain.Embeddings, [])[:model] || "nomic-embed-text"
  end

  defp configured_api_key do
    Application.get_env(:ai_brain, AIBrain.Embeddings, [])[:api_key]
  end

  defp do_embed(endpoint, model, text) when is_binary(text) do
    body = Jason.encode!(%{model: model, input: text})
    headers = build_headers()

    case Req.post(endpoint, body: body, headers: headers) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        extract_embedding(resp_body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Embeddings: API returned #{status}: #{inspect(body)}")
        {:error, "API returned #{status}"}

      {:error, reason} ->
        Logger.warning("Embeddings: request failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Embeddings: error: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp build_headers do
    headers = [{"Content-Type", "application/json"}]

    case configured_api_key() do
      nil -> headers
      key -> [{"Authorization", "Bearer #{key}"} | headers]
    end
  end

  defp extract_embedding(%{"data" => [%{"embedding" => emb} | _]}) when is_list(emb),
    do: {:ok, emb}

  defp extract_embedding(%{"data" => data}) when is_list(data) do
    # OpenAI format: data = [%{embedding: [...]}, ...]
    case List.first(data) do
      %{"embedding" => emb} when is_list(emb) -> {:ok, emb}
      _ -> {:error, :unexpected_response}
    end
  end

  defp extract_embedding(%{"embeddings" => [emb | _]}) when is_list(emb), do: {:ok, emb}

  defp extract_embedding(other) do
    Logger.warning("Embeddings: unexpected response format: #{inspect(other)}")
    {:error, :unexpected_response}
  end
end
