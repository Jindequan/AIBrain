defmodule AIBrain.Planning.SelfReview do
  @moduledoc """
  Orchestrates automated self-review of the AIBrain codebase.

  Loads the `self-review` skill from `Skill.Registry`, runs code analysis
  (Credo, tests, error-handling patterns), stores findings as episodic
  memories, and calls `Planner.plan/2` to create improvement goals and tasks.

  ## Usage

      # Full review cycle (analysis → memory → planner)
      AIBrain.Planning.SelfReview.run()

      # Analysis only, skip planner and memory
      AIBrain.Planning.SelfReview.run(dry_run: true)

      # Analysis only, return raw findings
      AIBrain.Planning.SelfReview.analyze()
  """

  require Logger

  alias AIBrain.Skill.Registry
  alias AIBrain.Planning.Planner
  alias AIBrain.Data.EpisodicMemories

  @doc """
  Run the full self-review cycle.

  ## Options

    * `:dry_run` — if true, skip Planner.plan() and episodic memory storage
    * `:timeout` — max time in ms for the planner (default: 300_000)
    * `:model` — provider model override for the planner
    * `:backend_dir` — path to the backend directory (default: `backend/`)

  ## Returns

    `{:ok, %{findings: map(), plan_id: String.t() | nil}}`
    or `{:error, String.t()}`
  """
  def run(opts \\ []) do
    Logger.info("SelfReview: starting self-review cycle")

    with {:ok, skill} <- load_skill(),
         {:ok, findings} <- analyze_codebase(opts),
         :ok <- maybe_store_memory(findings, opts),
         {:ok, plan} <- maybe_create_plan(skill, findings, opts) do
      Logger.info("SelfReview: completed")
      {:ok, %{findings: findings, plan_id: (plan && plan.session_id) || nil}}
    end
  end

  @doc """
  Run analysis only — no planner or memory storage.

  Returns raw findings map with keys `:credo`, `:tests`,
  `:error_handling`, and `:architecture`.
  """
  def analyze(opts \\ []) do
    {:ok, findings} = analyze_codebase(opts)
    findings
  end

  # ── Skill loading ──

  defp load_skill do
    case Registry.get("self-review") do
      {:ok, skill} ->
        Logger.info("SelfReview: loaded skill #{skill.name}")
        {:ok, skill}

      {:error, :not_found} ->
        Logger.warning("SelfReview: skill not found in registry, using defaults")
        {:ok, nil}
    end
  end

  # ── Code analysis ──

  defp analyze_codebase(opts) do
    backend = Keyword.get(opts, :backend_dir, "backend")

    findings = %{
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      backend_dir: backend,
      credo: run_credo(backend),
      tests: run_tests(backend),
      error_handling: analyze_error_handling(backend),
      architecture: analyze_architecture(backend)
    }

    {:ok, findings}
  end

  defp run_credo(backend) do
    case System.cmd("mix", ["credo", "--strict"],
           cd: backend,
           stderr_to_stdout: true,
           silence: true
         ) do
      {_output, 0} -> %{status: :clean, details: "No Credo warnings."}
      {output, _exit} -> %{status: :warnings, details: truncate_output(output)}
    end
  rescue
    e -> %{status: :error, details: "Credo not available: #{Exception.message(e)}"}
  end

  defp run_tests(backend) do
    case System.cmd("mix", ["test", "--trace"],
           cd: backend,
           stderr_to_stdout: true,
           silence: true,
           timeout: 120_000
         ) do
      {output, 0} ->
        %{status: :passed, details: summarize_test_output(output)}

      {output, _exit} ->
        %{status: :failed, details: summarize_test_output(output)}
    end
  rescue
    e -> %{status: :error, details: "Test run failed: #{Exception.message(e)}"}
  end

  defp summarize_test_output(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.filter(fn line ->
      String.contains?(line, ["test/", "FAILED", "** (", "warning:", "tests, "])
    end)
    |> Enum.take(30)
    |> Enum.join("\n")
  end

  defp analyze_error_handling(backend) do
    lib_path = Path.join(backend, "lib")

    rescue_patterns = find_patterns(lib_path, ~w(rescue try))
    error_tuples = find_patterns(lib_path, ~w({:error))
    catch_throw = find_patterns(lib_path, ~w(catch throw))

    %{
      rescue_occurrences: length(rescue_patterns),
      error_tuple_occurrences: length(error_tuples),
      catch_throw_occurrences: length(catch_throw),
      rescue_preview: strip_paths(Enum.take(rescue_patterns, 8)),
      error_tuple_preview: strip_paths(Enum.take(error_tuples, 8))
    }
  end

  defp find_patterns(lib_path, patterns) do
    Enum.flat_map(patterns, fn pattern ->
      case System.cmd("rg", ["-n", "--no-heading", pattern, lib_path], stderr_to_stdout: true) do
        {output, 0} -> String.split(output, "\n") |> Enum.filter(&(&1 != ""))
        _ -> []
      end
    end)
  rescue
    _ -> []
  end

  defp analyze_architecture(backend) do
    base = Path.join(backend, "lib/ai_brain")

    dirs = ~w(agent engine tool business skill core memory data planning)

    dir_sizes =
      Enum.map(dirs, fn dir ->
        abs = Path.join(base, dir)

        ex_files =
          if File.dir?(abs) do
            abs
            |> File.ls!()
            |> Enum.filter(&String.ends_with?(&1, ".ex"))
            |> Enum.count()
          else
            0
          end

        %{directory: dir, ex_files: ex_files}
      end)

    total =
      dir_sizes
      |> Enum.map(& &1.ex_files)
      |> Enum.sum()

    %{directories: dir_sizes, total_ex_files: total}
  end

  defp strip_paths(lines) do
    Enum.map(lines, fn line ->
      String.replace(line, ~r{^.*/lib/ai_brain/}, "lib/ai_brain/")
    end)
  end

  defp truncate_output(output) do
    String.slice(output, 0, 2000)
  end

  # ── Memory storage ──

  defp maybe_store_memory(_findings, opts) do
    if Keyword.get(opts, :dry_run), do: :ok, else: store_episodic_memory()
  end

  defp store_episodic_memory do
    narrative =
      "Executed automated self-review of AIBrain. " <>
        "Analyzed code quality (Credo), test suite, error-handling " <>
        "patterns, and module architecture."

    case EpisodicMemories.create(%{
           narrative: narrative,
           objective: "Automated codebase self-review",
           approach:
             "Code analysis using mix credo, mix test, ripgrep pattern search, and directory enumeration",
           tags: ["self_review"],
           importance_score: 5.0,
           success_score: 0.0
         }) do
      {:ok, memory} ->
        Logger.info("SelfReview: stored episodic memory #{memory.id}")
        :ok

      {:error, reason} ->
        Logger.warning("SelfReview: episodic memory storage failed: #{inspect(reason)}")
        :ok
    end
  end

  # ── Planning ──

  defp maybe_create_plan(_skill, _findings, opts) do
    if Keyword.get(opts, :dry_run), do: {:ok, nil}, else: create_improvement_plan(opts)
  end

  defp create_improvement_plan(opts) do
    Planner.plan(build_prompt(), Keyword.take(opts, [:timeout, :model]))
  end

  defp build_prompt do
    ~s"""
    Perform an automated self-review of the AIBrain Elixir codebase.

    The review skill defines a four-phase process:

    1. Architecture Review — evaluate separation of concerns, module size (>300 lines),
       and circular dependencies in agent/, engine/, tool/, business/, skill/, core/, memory/
    2. Code Quality — run mix credo --strict and mix test --trace to find warnings
       and test failures
    3. Error Handling — search for rescue, {:error tuples, bare rescue _ clauses,
       and inconsistent error patterns in GenServers
    4. Create Improvement Goals — using create_goal and add_task tools, create
       up to 5 priorities ranked by severity (bugs first, then architecture,
       then code quality, then nice-to-haves)

    After analyzing, call complete_plan with a summary of all findings.
    """
  end
end
