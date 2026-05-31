defmodule AIBrain.Settings do
  @moduledoc """
  User settings persisted to ~/.aibrain/settings.json.

  All user-facing toggles live here — not in Application config.
  Theme, notification preferences, etc.
  """

  @defaults %{
    "theme" => "light",
    "notifications_enabled" => true,
    "language" => "zh"
  }

  @path Path.join(System.user_home!(), ".aibrain/settings.json")

  # ── Public API ──────────────────────────────────────────────

  def get(key, default \\ nil) do
    all() |> Map.get(key, default)
  end

  def all do
    case File.read(@path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, map} when is_map(map) -> Map.merge(@defaults, map)
          _ -> @defaults
        end

      {:error, _} ->
        @defaults
    end
  end

  def put(key, value) do
    current = all()
    updated = Map.put(current, to_string(key), value)
    save(updated)
  end

  def merge(map) when is_map(map) do
    current = all()
    updated = Map.merge(current, map)
    save(updated)
  end

  def reset do
    save(@defaults)
  end

  # ── Internal ────────────────────────────────────────────────

  defp save(map) do
    File.mkdir_p!(Path.dirname(@path))
    File.write!(@path, Jason.encode!(map, pretty: true))
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end
end
