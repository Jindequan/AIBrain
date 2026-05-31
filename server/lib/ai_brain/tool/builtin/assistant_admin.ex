defmodule AIBrain.Tool.Builtin.AssistantAdmin do
  @behaviour AIBrain.Tool.Behaviour
  require Logger

  alias AIBrain.Skill.Registry, as: SkillRegistry
  alias AIBrain.Data.Runs

  def name, do: "admin"

  def description do
    "Load skills and manage runs. Use `load_skill` to fetch a skill's full instructions when you need domain expertise. " <>
      "Use `list_skills` to see available skills. Supports: list_skills, load_skill, get_skill, list_runs, get_run"
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "operation" => %{
          "type" => "string",
          "enum" => ~w(list_skills load_skill get_skill list_runs get_run),
          "description" => "load_skill: fetch full skill body for domain work. list_skills: see available skills. get_skill: quick metadata preview. list_runs/get_run: check run status."
        },
        "name" => %{
          "type" => "string",
          "description" => "Skill name, e.g. 'research', 'coding', 'creative', 'project', 'life-admin' (for load_skill, get_skill)"
        },
        "run_id" => %{
          "type" => "string",
          "description" => "Run ID (for get_run)"
        }
      },
      "required" => ["operation"]
    }
  end

  def read_only?, do: false

  def execute(%{"operation" => op} = args, _context) do
    case op do
      "list_skills" -> list_skills(args)
      "load_skill" -> load_skill(args)
      "get_skill" -> get_skill(args)
      "list_runs" -> list_runs()
      "get_run" -> get_run(args)
      _ -> {:error, "Unknown operation: #{op}"}
    end
  end

  def execute(args, _context) do
    {:error, "Missing required 'operation' field. Got: #{inspect(args)}"}
  end

  # ── Implementations ──

  defp list_skills(_args) do
    specs = SkillRegistry.list()

    result =
      Enum.map(specs, fn s ->
        %{name: s.name, description: s.description, status: s.status}
      end)

    {:ok, Jason.encode!(result)}
  end

  defp load_skill(%{"name" => name}) do
    case SkillRegistry.get(name) do
      {:ok, spec} ->
        {:ok,
         Jason.encode!(%{
           name: spec.name,
           description: spec.description,
           body: spec.body || ""
         })}

      {:error, :not_found} ->
        {:error, "Skill not found: #{name}. Use list_skills to see available skills."}
    end
  end

  defp get_skill(%{"name" => name}) do
    case SkillRegistry.get(name) do
      {:ok, spec} ->
        {:ok,
         Jason.encode!(%{
           name: spec.name,
           description: spec.description,
           status: spec.status,
           origin: spec.origin,
           source_uri: spec.source_uri
         })}

      {:error, :not_found} ->
        {:error, "Skill not found: #{name}"}
    end
  end

  defp list_runs do
    runs = Runs.list_runs(source_type: "task", status: ["running", "pending"])

    result =
      Enum.map(runs, fn r ->
        %{
          run_id: r.id,
          status: r.status,
          started_at: r.started_at
        }
      end)

    {:ok, Jason.encode!(result)}
  end

  defp get_run(%{"run_id" => run_id}) do
    case Runs.get_run(run_id) do
      {:ok, run} ->
        {:ok,
         Jason.encode!(%{
           run_id: run.id,
           status: run.status,
           input: run.input,
           output: run.output,
           error: run.error,
           started_at: run.started_at,
           completed_at: run.completed_at
         })}

      {:error, :not_found} ->
        {:error, "Run not found: #{run_id}"}
    end
  end
end
