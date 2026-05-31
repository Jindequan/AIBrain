defmodule AIBrain.Memory.Stores.Workspace do
  @moduledoc """
  Memory store adapter for workspace files.

  Searches workspace files for relevant content.
  """

  @behaviour AIBrain.Memory.Store

  alias AIBrain.Memory.Entry

  @impl true
  def source, do: :workspace

  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 3)

    workspace_root = resolve_workspace_root()

    if workspace_root && File.dir?(workspace_root) do
      workspace_root
      |> list_text_files()
      |> Enum.flat_map(&search_file(&1, query))
      |> Enum.sort_by(& &1.confidence, :desc)
      |> Enum.take(limit)
    else
      []
    end
  end

  @impl true
  def count do
    workspace_root = resolve_workspace_root()

    if workspace_root && File.dir?(workspace_root) do
      list_text_files(workspace_root) |> length()
    else
      0
    end
  end

  defp resolve_workspace_root do
    case Application.get_env(:ai_brain, :data_dir) do
      nil -> Path.join(System.user_home(), ".aibrain/workspace")
      dir -> Path.join(dir, "workspace")
    end
  end

  defp list_text_files(root) do
    root = root || resolve_workspace_root()

    if root && File.dir?(root) do
      root
      |> Path.join("**/*.{md,txt}")
      |> Path.wildcard()
      |> Enum.take(20)
    else
      []
    end
  end

  defp search_file(path, query) do
    case File.read(path) do
      {:ok, content} when byte_size(content) < 100_000 ->
        if keyword_match?(content, query) do
          snippet = extract_snippet(content, query)
          score = relevance_score(snippet, query)

          [
            Entry.new(%{
              id: "ws-#{:crypto.hash(:sha256, path) |> Base.encode16(case: :lower, length: 8)}",
              source: :workspace,
              type: :document,
              content: snippet,
              confidence: score,
              decay_score: 1.0,
              metadata: %{source_file: path}
            })
          ]
        else
          []
        end

      _ ->
        []
    end
  end

  defp keyword_match?(content, query) do
    String.contains?(String.downcase(content), String.downcase(query))
  end

  defp extract_snippet(content, query) do
    idx = content |> String.downcase() |> :binary.match(String.downcase(query))

    case idx do
      {pos, _len} ->
        start_pos = max(0, pos - 100)
        end_pos = min(String.length(content), pos + 300)
        "..." <> String.slice(content, start_pos, end_pos - start_pos) <> "..."

      :nomatch ->
        String.slice(content, 0, 300)
    end
  end

  defp relevance_score(snippet, _query) do
    # Simple scoring: shorter, more focused snippets score higher
    len = String.length(snippet)

    cond do
      len < 200 -> 0.6
      len < 500 -> 0.4
      true -> 0.2
    end
  end
end
