defmodule AIBrain.RAG.Retriever do
  @moduledoc """
  Retrieves relevant RAG chunks for a query using vector similarity.

  Falls back to keyword search if no embeddings are available.

  ## Configuration

  These application config values control search behavior:

      config :ai_brain,
        rag_search_limit: 500,            # rows to fetch per batch
        rag_similarity_threshold: 0.3     # minimum cosine similarity score
  """

  require Logger
  alias AIBrain.Embeddings

  @doc """
  Retrieve the top N chunks relevant to the query text.

  Options:
    - :limit — max chunks (default 5, max 100)
    - :source_type — optional filter by source type (e.g., "elixir", "markdown")

  Returns list of %{id: binary, source: binary, content: binary, similarity: float, metadata: map}.
  """
  def retrieve(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5) |> min(100)
    source_type = Keyword.get(opts, :source_type)
    threshold = Application.get_env(:ai_brain, :rag_similarity_threshold, 0.3)

    with {:ok, query_vector} <- Embeddings.embed(query),
         {:ok, entries} <- vector_search(query_vector, limit, source_type, threshold) do
      entries
    else
      {:error, :not_configured} ->
        keyword_search(query, limit, source_type)

      _ ->
        keyword_search(query, limit, source_type)
    end
  end

  defp vector_search(query_vector, limit, source_type, threshold) do
    search_limit = Application.get_env(:ai_brain, :rag_search_limit, 500)

    where_clause =
      if source_type do
        "WHERE embedding IS NOT NULL AND source_type = ?"
      else
        "WHERE embedding IS NOT NULL"
      end

    where_params = if source_type, do: [source_type], else: []

    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        AIBrain.Repo,
        "SELECT COUNT(*) FROM rag_chunks #{where_clause}",
        where_params
      )

    num_batches = max(1, div(count + search_limit - 1, search_limit))

    all_scored =
      Enum.flat_map(0..(num_batches - 1), fn batch_idx ->
        offset = batch_idx * search_limit

        fetch_sql = """
        SELECT id, source, content, embedding, metadata FROM rag_chunks #{where_clause}
        LIMIT ? OFFSET ?
        """

        result =
          Ecto.Adapters.SQL.query!(
            AIBrain.Repo,
            fetch_sql,
            where_params ++ [search_limit, offset]
          )

        Enum.map(result.rows, fn [id, source, content, embedding_blob, metadata_json] ->
          embedding = Embeddings.decode_blob(embedding_blob)

          %{
            id: id,
            source: source,
            content: content,
            similarity: Embeddings.cosine_similarity(query_vector, embedding),
            metadata: decode_json(metadata_json)
          }
        end)
      end)

    scored =
      all_scored
      |> Enum.filter(&(&1.similarity >= threshold))
      |> Enum.sort_by(& &1.similarity, :desc)
      |> Enum.take(limit)

    {:ok, scored}
  rescue
    e ->
      Logger.error("AIBrain.RAG.Retriever.vector_search failed: #{Exception.message(e)}")
      {:error, :search_failed}
  end

  defp keyword_search(query, limit, source_type) do
    search_limit = Application.get_env(:ai_brain, :rag_search_limit, 500)
    words = String.split(query)

    like_conditions = Enum.map(words, fn _ -> "content LIKE ?" end)
    like_params = Enum.map(words, fn word -> "%#{word}%" end)

    source_clause = if source_type, do: "AND source_type = ?", else: ""
    source_params = if source_type, do: [source_type], else: []

    sql = """
    SELECT id, source, content, metadata FROM rag_chunks
    WHERE #{Enum.join(like_conditions, " AND ")} #{source_clause}
    LIMIT ?
    """

    params = like_params ++ source_params ++ [search_limit]

    result = Ecto.Adapters.SQL.query!(AIBrain.Repo, sql, params)

    query_words_lower = MapSet.new(String.split(String.downcase(query)))

    scored =
      result.rows
      |> Enum.map(fn [id, source, content, metadata_json] ->
        content_lower = String.downcase(content)
        words_in_content = MapSet.new(String.split(content_lower))
        overlap = MapSet.intersection(query_words_lower, words_in_content) |> MapSet.size()

        %{
          id: id,
          source: source,
          content: content,
          similarity: overlap,
          metadata: decode_json(metadata_json)
        }
      end)
      |> Enum.sort_by(& &1.similarity, :desc)
      |> Enum.take(limit)

    scored
  rescue
    e ->
      Logger.error("AIBrain.RAG.Retriever.keyword_search failed: #{Exception.message(e)}")
      []
  end

  defp decode_json(nil), do: %{}

  defp decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end
end
