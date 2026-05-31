defmodule AIBrain.Web.Handlers.MemoryHandler do
  import Plug.Conn
  require Logger
  alias AIBrain.Data.EpisodicMemories
  alias AIBrain.KnowledgeWiki

  def handle_list(conn, params) do
    type = Map.get(params, "type")

    case type do
      "episodic" ->
        entries = list_episodic(params)
        json(conn, 200, %{entries: Enum.map(entries, &serialize_episodic/1)})

      _ ->
        entries = KnowledgeWiki.list(type: type)
        json(conn, 200, %{entries: entries})
    end
  end

  def handle_get(conn, id) do
    entries = KnowledgeWiki.list()

    case Enum.find(entries, fn e -> e.id == id end) do
      nil -> json(conn, 404, %{error: "Memory entry not found"})
      entry -> json(conn, 200, entry)
    end
  end

  def handle_create(conn, params) do
    case KnowledgeWiki.create_entry(params) do
      {:ok, entry} -> json(conn, 201, entry)
      {:error, :empty_content} -> json(conn, 422, %{error: "Content cannot be empty"})
      {:error, :duplicate} -> json(conn, 409, %{error: "Duplicate entry"})
      {:error, _} -> json(conn, 500, %{error: "Failed to create entry"})
    end
  end

  def handle_update(conn, id, params) do
    attrs = Map.take(params, ["usable_for_auto_decision", "source_detail", "confidence"])

    case KnowledgeWiki.update_entry(id, attrs) do
      :ok ->
        # Re-fetch and return the updated entry
        entries = KnowledgeWiki.list()

        case Enum.find(entries, fn e -> e.id == id end) do
          nil -> json(conn, 200, %{message: "Updated"})
          entry -> json(conn, 200, entry)
        end

      {:error, reason} ->
        Logger.error("Failed to update memory entry: #{inspect(reason)}")
        json(conn, 422, %{error: "Failed to update memory entry"})
    end
  end

  def handle_delete(conn, id) do
    case KnowledgeWiki.delete(id) do
      :ok -> json(conn, 200, %{message: "Deleted"})
      {:error, :not_found} -> json(conn, 404, %{error: "Entry not found"})
    end
  end

  defp list_episodic(params) do
    limit = params |> Map.get("limit") |> parse_int(20) |> clamp_limit(1, 100)

    case Map.get(params, "goal_id") do
      goal_id when is_binary(goal_id) and goal_id != "" ->
        EpisodicMemories.get_by_goal(goal_id, limit: limit)

      _ ->
        EpisodicMemories.list_recent(limit)
    end
  end

  defp serialize_episodic(memory) do
    %{
      id: memory.id,
      type: "episodic",
      goal_id: memory.goal_id,
      task_id: memory.task_id,
      run_id: memory.run_id,
      narrative: memory.narrative,
      objective: memory.objective,
      approach: memory.approach,
      lessons: memory.lessons || [],
      tags: memory.tags || [],
      success_score: memory.success_score,
      importance_score: memory.importance_score,
      inserted_at: memory.inserted_at,
      updated_at: memory.updated_at
    }
  end

  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp parse_int(_value, default), do: default

  defp clamp_limit(value, min, max) do
    value
    |> Kernel.max(min)
    |> Kernel.min(max)
  end

  defp json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(data))
  end
end
