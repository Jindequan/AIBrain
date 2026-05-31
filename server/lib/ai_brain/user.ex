defmodule AIBrain.User do
  @moduledoc """
  Single-source-of-truth module for user identity, preferences, and profile.

  Merges data from three sources (highest priority first):
    1. `~/.aibrain/user.md` — explicit YAML frontmatter fields
    2. DB `users` table — set via HTTP API or ProxyControl
    3. `AIBrain.Memory.UserProfile` — learned profile via memory extraction
    4. Sensible defaults

  The DB row is the authoritative base layer; user.md and UserProfile
  override or supplement it.  Returns `id` from the DB so interactions
  and events can attribute decisions to a real user identity.
  """

  alias AIBrain.Data.Users
  alias AIBrain.Memory.UserProfile

  @doc """
  Returns the current user's profile as a map.

  Merge priority (highest to lowest):
    1. `~/.aibrain/user.md` — explicit YAML frontmatter fields
    2. DB `users` table — set via HTTP API or ProxyControl
    3. `AIBrain.Memory.UserProfile` — learned profile via memory extraction
    4. Sensible defaults

  Includes `id` from the DB for traceability in interactions and events.
  """
  def current do
    {:ok, db_user} = Users.get()
    profile = UserProfile.load()
    {md_map, md_prefs} = extract_md_overrides()

    name = md_map["name"] || db_user.name || profile.name
    phase = md_map["current_phase"] || profile.current_phase

    prefs =
      default_preferences()
      |> Map.merge(profile.preferences)
      |> Map.merge(db_user.preferences || %{})
      |> Map.merge(md_prefs)

    %{
      id: db_user.id,
      name: name,
      preferences: prefs,
      habits: profile.habits,
      relationships: profile.relationships,
      devices: profile.devices,
      current_phase: phase,
      updated_at: profile.updated_at
    }
  end

  @doc """
  Returns a map of user preferences.

  Combines preferences from all sources, with `~/.aibrain/user.md` taking
  priority over the learned profile, and both overriding defaults.
  """
  def preferences do
    current()[:preferences] || default_preferences()
  end

  @doc """
  Returns profile text suitable for injecting into LLM context.

  Unlike `AIBrain.Memory.UserProfile.format_for_prompt/1`, this returns
  just the bullet-point text without a section header.  Callers such as
  `AIBrain.Context.Prepared` wrap their own `## User Profile` header.

  Returns `""` when no profile data is available (so callers can fall
  through gracefully).
  """
  def profile_text do
    user = current()
    parts = build_profile_parts(user)

    case parts do
      [] -> ""
      _ -> Enum.join(parts, "\n")
    end
  end

  @doc """
  Returns the user's default workspace path.

  Priority:
    1. `:ai_brain, :workspace_path` application config
    2. `workspace_path` from user preferences
    3. `System.user_home/0`
  """
  def workspace do
    case Application.get_env(:ai_brain, :workspace_path) do
      nil ->
        prefs = preferences()
        Map.get(prefs, "workspace_path", System.user_home())

      path when is_binary(path) ->
        path
    end
  end

  # ── Private ───────────────────────────────────────────────────────

  defp default_preferences do
    %{
      "language" => "zh",
      "communication_style" => "medium"
    }
  end

  defp extract_md_overrides do
    case load_user_md() do
      {:ok, md_map} ->
        prefs = Map.drop(md_map, ["name", "current_phase"])
        {md_map, prefs}

      :not_found ->
        {%{}, %{}}
    end
  end

  defp load_user_md do
    path = Path.join(System.user_home(), ".aibrain/user.md")

    case File.read(path) do
      {:ok, content} ->
        case parse_yaml_frontmatter(content) do
          {:ok, map} when map != %{} -> {:ok, map}
          _ -> :not_found
        end

      _ ->
        :not_found
    end
  end

  defp parse_yaml_frontmatter(content) do
    trimmed = String.trim_leading(content)

    case Regex.run(~r/^---\s*\n(.*?)\n---/s, trimmed) do
      [_, body] ->
        pairs =
          body
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ":", parts: 2) do
              [key, val] ->
                k = String.trim(key)
                v = String.trim(val) |> String.trim("\"'")
                Map.put(acc, k, v)

              _ ->
                acc
            end
          end)

        {:ok, pairs}

      nil ->
        :not_found
    end
  end

  defp build_profile_parts(user) do
    []
    |> maybe_add_part("Name", user[:name])
    |> maybe_add_part("Communication style", get_in(user, [:preferences, "communication_style"]))
    |> maybe_add_part("Code style", get_in(user, [:preferences, "code_style"]))
    |> maybe_add_part("Language", get_in(user, [:preferences, "language"]))
    |> maybe_add_part("Current focus", user[:current_phase])
    |> maybe_add_habits_part(user[:habits])
    |> maybe_add_devices_part(user[:devices])
  end

  defp maybe_add_part(list, _label, nil), do: list
  defp maybe_add_part(list, _label, ""), do: list
  defp maybe_add_part(list, label, value), do: list ++ ["- **#{label}:** #{value}"]

  defp maybe_add_habits_part(list, nil), do: list
  defp maybe_add_habits_part(list, []), do: list

  defp maybe_add_habits_part(list, habits) do
    habit_lines = Enum.map(habits, &"- #{&1["pattern"] || inspect(&1)}")
    list ++ ["- **Habits:**" | habit_lines]
  end

  defp maybe_add_devices_part(list, nil), do: list
  defp maybe_add_devices_part(list, []), do: list

  defp maybe_add_devices_part(list, devices) do
    device_lines = Enum.map(devices, &"- #{&1.name || inspect(&1)}")
    list ++ ["- **Devices:**" | device_lines]
  end
end
