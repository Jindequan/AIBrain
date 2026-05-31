defmodule AIBrain.AgentRuntime.Evidence do
  @moduledoc """
  Evidence ledger: record, query, and summarize factual evidence for a run.

  Long source excerpts (> 2KB) are written to FileStore and only the path
  is stored in the database. This keeps the evidence table lightweight.
  """

  require Logger

  alias AIBrain.AgentRuntime.FileStore
  alias AIBrain.Data.EvidenceItems

  @excerpt_threshold 2_048

  @doc """
  Record one piece of evidence. Large `excerpt` values are written to
  FileStore automatically; only the file path goes into the DB.

  Returns `{:ok, evidence}` or `{:error, changeset}`.
  """
  def record(attrs) when is_map(attrs) do
    attrs = maybe_offload_excerpt(attrs)
    EvidenceItems.create(attrs)
  end

  @doc """
  Record multiple evidence items in sequence. Returns `{:ok, items}` if all
  succeed, or `{:error, failures}` with a list of failed items.
  """
  def record_many(items) when is_list(items) do
    results =
      Enum.map(items, fn attrs ->
        case record(attrs) do
          {:ok, evidence} -> {:ok, evidence}
          {:error, reason} -> {:error, attrs, reason}
        end
      end)

    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    if Enum.empty?(failures) do
      {:ok, for({:ok, e} <- results, do: e)}
    else
      {:error, failures}
    end
  end

  @doc """
  List all evidence items for a run.
  """
  def list_for_run(run_id) when is_binary(run_id) do
    EvidenceItems.list_for_run(run_id)
  end

  @doc """
  Build a text summary of evidence for injection into the LLM prompt.

  Active evidence items are rendered as bullet points. Items with
  `source_excerpt_path` are loaded from FileStore if the file exists.
  """
  def summarize_for_prompt(run_id) when is_binary(run_id) do
    items = EvidenceItems.list_active_for_run(run_id)

    if Enum.empty?(items) do
      "No evidence recorded for this run."
    else
      lines =
        Enum.map(items, fn item ->
          source = "[#{item.source_type}#{source_suffix(item)}]"
          conf = Float.round(item.confidence || 0.5, 2)
          "- #{source} (#{conf}) #{truncate_claim(item.claim)}"
        end)

      "## Evidence (#{length(items)} items)\n#{Enum.join(lines, "\n")}"
    end
  end

  @doc """
  Count evidence items for a run.
  """
  def count(run_id) when is_binary(run_id) do
    EvidenceItems.count_for_run(run_id)
  end

  defp maybe_offload_excerpt(attrs) do
    excerpt = Map.get(attrs, :excerpt) || Map.get(attrs, "excerpt")

    case excerpt do
      excerpt when is_binary(excerpt) and byte_size(excerpt) > @excerpt_threshold ->
        run_id = Map.get(attrs, :run_id) || Map.get(attrs, "run_id")

        case write_excerpt(run_id, excerpt) do
          {:ok, path} -> Map.put(attrs, :source_excerpt_path, path)
          {:error, _} -> attrs
        end

      _ ->
        attrs
    end
  end

  defp write_excerpt(run_id, excerpt) do
    dir = Path.join(FileStore.run_dir(run_id), "evidence")
    filename = "#{:erlang.unique_integer([:positive])}.txt"
    path = Path.join(dir, filename)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, excerpt) do
      {:ok, path}
    else
      {:error, reason} ->
        Logger.warning("Evidence: failed to offload excerpt to #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp source_suffix(%{tool_name: name}) when is_binary(name) and name != "", do: ":#{name}"
  defp source_suffix(%{source_uri: uri}) when is_binary(uri) and uri != "", do: ":#{uri}"
  defp source_suffix(_), do: ""

  defp truncate_claim(claim) when is_binary(claim) and byte_size(claim) > 200 do
    String.slice(claim, 0, 200) <> "..."
  end

  defp truncate_claim(claim) when is_binary(claim), do: claim
  defp truncate_claim(_), do: "(no claim)"
end
