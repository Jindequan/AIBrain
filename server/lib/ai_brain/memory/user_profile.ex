defmodule AIBrain.Memory.UserProfile do
  @moduledoc """
  Continuously updated user profile extracted from memory entries.

  Builds a structured profile (preferences, habits, relationships, devices,
  current phase) by mining KnowledgeWiki entries and session data.

  Persisted to ~/.aibrain/workspace/profile.json for survival across restarts.
  """

  require Logger

  defstruct [
    :name,
    preferences: %{},
    habits: [],
    relationships: [],
    devices: [],
    current_phase: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          preferences: map(),
          habits: [map()],
          relationships: [map()],
          devices: [map()],
          current_phase: String.t() | nil,
          updated_at: String.t() | nil
        }

  @doc """
  Load the current user profile from disk, or return an empty one.
  """
  def load do
    path = profile_path()

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, data} -> struct(__MODULE__, data)
          _ -> %__MODULE__{}
        end

      _ ->
        %__MODULE__{}
    end
  end

  @doc """
  Update the user profile with new knowledge entries.

  Scans entries for preferences, facts, and task outcomes,
  merging them into the profile and persisting to disk.
  """
  def update_from_entries(profile, entries) when is_list(entries) do
    profile
    |> extract_preferences(entries)
    |> extract_facts(entries)
    |> extract_phase_hints(entries)
    |> tap(&persist/1)
  end

  @doc """
  Format the user profile for LLM context injection.
  """
  def format_for_prompt(%__MODULE__{} = profile) do
    parts =
      []
      |> maybe_add("Name", profile.name)
      |> maybe_add("Communication style", profile.preferences["communication_style"])
      |> maybe_add("Code style", profile.preferences["code_style"])
      |> maybe_add("Current focus", profile.current_phase)
      |> maybe_add_habits(profile.habits)
      |> maybe_add_devices(profile.devices)

    if parts == [] do
      ""
    else
      (["## User Profile (continuously updated from past interactions)", ""] ++ parts)
      |> Enum.join("\n")
    end
  end

  # ── Extraction ──────────────────────────────────────────────────

  defp extract_preferences(profile, entries) do
    entries
    |> Enum.filter(&(&1.type == :preference))
    |> Enum.reduce(profile, fn entry, acc ->
      content = String.downcase(entry.content)

      new_prefs =
        cond do
          String.contains?(content, "prefer") and String.contains?(content, "concise") ->
            Map.put(acc.preferences, "communication_style", "concise")

          String.contains?(content, "prefer") and String.contains?(content, "detailed") ->
            Map.put(acc.preferences, "communication_style", "detailed")

          String.contains?(content, "code") and String.contains?(content, "functional") ->
            Map.put(acc.preferences, "code_style", "functional")

          String.contains?(content, "code") and String.contains?(content, "object-oriented") ->
            Map.put(acc.preferences, "code_style", "object-oriented")

          true ->
            # Store generic preference
            pref_key = extract_preference_key(content)

            if pref_key do
              Map.put(acc.preferences, pref_key, String.slice(entry.content, 0, 100))
            else
              acc.preferences
            end
        end

      %{acc | preferences: new_prefs}
    end)
  end

  defp extract_facts(profile, entries) do
    entries
    |> Enum.filter(&(&1.type == :fact))
    |> Enum.reduce(profile, fn entry, acc ->
      content_lower = String.downcase(entry.content)

      cond do
        String.contains?(content_lower, "name is") ->
          name = extract_after(entry.content, "name is")
          %{acc | name: String.trim(name)}

        String.contains?(content_lower, "works as") or String.contains?(content_lower, "work as") ->
          role = extract_after(entry.content, ["works as", "work as"])
          %{acc | current_phase: String.trim(role)}

        String.contains?(content_lower, "hostname") or String.contains?(content_lower, "macbook") ->
          device = %{name: String.slice(entry.content, 0, 100), confidence: entry.confidence}
          %{acc | devices: [device | acc.devices] |> Enum.take(3)}

        true ->
          acc
      end
    end)
  end

  defp extract_phase_hints(profile, entries) do
    entries
    |> Enum.filter(&(&1.type == :task_outcome))
    |> Enum.reduce(profile, fn entry, acc ->
      content = String.downcase(entry.content)

      cond do
        String.contains?(content, "aibrain") ->
          %{acc | current_phase: "Building AIBrain"}

        String.contains?(content, "interview") or String.contains?(content, "job") ->
          %{acc | current_phase: "Job searching"}

        true ->
          acc
      end
    end)
  end

  # ── Persistence ─────────────────────────────────────────────────

  defp profile_path do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home(), ".aibrain"))

    Path.join([data_dir, "workspace", "profile.json"])
  end

  defp persist(%__MODULE__{} = profile) do
    profile = %{profile | updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}

    json =
      profile
      |> Map.from_struct()
      |> Jason.encode!()

    path = profile_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, json)

    profile
  rescue
    e ->
      Logger.warning("Memory.UserProfile persist failed: #{Exception.message(e)}")
      profile
  end

  # ── Formatting helpers ──────────────────────────────────────────

  defp maybe_add(list, _label, nil), do: list
  defp maybe_add(list, _label, ""), do: list
  defp maybe_add(list, label, value), do: list ++ ["- **#{label}:** #{value}"]

  defp maybe_add_habits(list, []), do: list

  defp maybe_add_habits(list, habits) do
    habit_lines = Enum.map(habits, &"- #{&1["pattern"] || inspect(&1)}")
    list ++ ["- **Habits:**" | habit_lines]
  end

  defp maybe_add_devices(list, []), do: list

  defp maybe_add_devices(list, devices) do
    device_lines = Enum.map(devices, &"- #{&1.name || inspect(&1)}")
    list ++ ["- **Devices:**" | device_lines]
  end

  defp extract_preference_key(content) do
    cond do
      String.contains?(content, "editor") -> "editor"
      String.contains?(content, "language") -> "language"
      String.contains?(content, "theme") -> "theme"
      true -> nil
    end
  end

  defp extract_after(content, target) when is_list(target) do
    Enum.find_value(target, fn t ->
      case :binary.match(content, t) do
        {pos, len} ->
          content
          |> String.slice((pos + len)..-1//1)
          |> String.trim()
          |> String.replace(~r/[.,;!].*/, "")
          |> String.trim()

        :nomatch ->
          nil
      end
    end) || ""
  end

  defp extract_after(content, target) when is_binary(target) do
    extract_after(content, [target])
  end
end
