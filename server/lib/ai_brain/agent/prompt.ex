defmodule AIBrain.Agent.Prompt do
  @moduledoc """
  Build the system prompt for the agent by layering components in fixed order.

  Prompt hierarchy:
    [Layer 1]      Core identity          (FROZEN — AIBrain.Prompts.identity/0)
    [Layer 1.25]   Personality style      (WARM  — AIBrain.Prompts.personality/1)
    [Layer 1.5]    Skill catalog          (FROZEN — skill names + descriptions)
    [Layer 2]      Selected skill bodies  (DYNAMIC — per required_skills)
    [Layer 3]      Episodic context       (DYNAMIC — per goal)
  """

  require Logger

  alias AIBrain.Skill.Registry, as: SkillRegistry

  @doc """
  Build the full system prompt.

  `context` may contain:
    - :messages - conversation history (for mode detection)
    - :tools_count - hint for mode detection
    - :required_skills - list of skill names to expand into body text
    - :task_description - optional, for skill catalog context
    - :goal_id - optional, for episodic memory injection
  """
  def build(context \\ %{}) do
    required_skills = Map.get(context, :required_skills, [])
    task_description = Map.get(context, :task_description)

    sections = [
      # Layer 1: Core identity
      AIBrain.Prompts.identity(),
      # Layer 1.25: Personality (mode-adaptive)
      build_personality(context),
      # Layer 1.5: Skill catalog
      build_skill_catalog(task_description),
      # Layer 2: Selected skill bodies
      resolve_skill_bodies(required_skills),
      # Layer 3: Episodic context
      build_episodic_context(Map.get(context, :goal_id))
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # ── Personality ──

  defp build_personality(_context) do
    try do
      AIBrain.Prompts.personality()
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  # ── Skill Catalog ──

  defp build_skill_catalog(_task_description) do
    try do
      skills = SkillRegistry.list_active()

      if skills == [] do
        nil
      else
        lines =
          Enum.map(skills, fn s ->
            "- **#{s.name}** — #{s.description}"
          end)

        header = "## Available Skills\n\n" <>
          "Load a skill with the `admin` tool (operation: `load_skill`, name: skill name) when the user's request " <>
          "matches its domain. Loading gives you the full methodology, tool guidance, and boundaries for that domain. " <>
          "You may load multiple skills in one session if the task spans domains.\n\n" <>
          "Catalog:\n"

        header <> Enum.join(lines, "\n")
      end
    rescue
      e ->
        Logger.warning("Agent.Prompt skill catalog failed: #{Exception.message(e)}")
        nil
    catch
      :exit, _ -> nil
    end
  end

  defp resolve_skill_bodies([]), do: nil

  defp resolve_skill_bodies(names) when is_list(names) do
    bodies =
      Enum.flat_map(names, fn name ->
        try do
          case SkillRegistry.get(name) do
            {:ok, %{status: :active, body: body}} when is_binary(body) and body != "" ->
              ["## Skill: #{name}\n\n#{body}"]

            _ ->
              []
          end
        rescue
          _ -> []
        catch
          :exit, _ -> []
        end
      end)

    if bodies == [], do: nil, else: Enum.join(bodies, "\n\n")
  end

  # ── Episodic Context ──

  defp build_episodic_context(nil), do: nil

  defp build_episodic_context(goal_id) do
    episodes =
      try do
        {:ok, entries} = AIBrain.Memory.recall(goal_id, type: :episodic, limit: 5)
        entries
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    if episodes == [] do
      nil
    else
      lines =
        Enum.map(episodes, fn e ->
          period_str = format_period(e[:metadata][:period_start], e[:metadata][:period_end])

          lessons_str =
            if e[:lessons] && e[:lessons] != [] do
              "\n    Lessons: #{Enum.join(e[:lessons], "; ")}"
            else
              ""
            end

          decisions_str =
            if e[:metadata][:key_decisions] && e[:metadata][:key_decisions] != %{} &&
                 e[:metadata][:key_decisions] != [] do
              decisions =
                e[:metadata][:key_decisions]
                |> List.wrap()
                |> Enum.map(fn d -> "(#{Map.get(d, "decision", Map.get(d, :decision, "?"))})" end)
                |> Enum.join(", ")

              "\n    Key decisions: #{decisions}"
            else
              ""
            end

          score_str =
            if e[:metadata][:success_score],
              do: " (score: #{Float.round(e[:metadata][:success_score], 2)})",
              else: ""

          "#{period_str}#{e[:content]}#{score_str}#{lessons_str}#{decisions_str}"
        end)

      "## Previous Goal Context\n\nThe following are previous episodes from this goal's history:\n" <>
        Enum.join(lines, "\n")
    end
  end

  defp format_period(nil, nil), do: ""

  defp format_period(start_dt, end_dt) do
    fmt = fn dt ->
      dt
      |> DateTime.to_naive()
      |> NaiveDateTime.to_string()
      |> String.slice(0, 16)
      |> String.replace("T", " ")
    end

    cond do
      start_dt && end_dt -> "[#{fmt.(start_dt)} ~ #{fmt.(end_dt)}] "
      start_dt -> "[#{fmt.(start_dt)}] "
      true -> ""
    end
  end
end
