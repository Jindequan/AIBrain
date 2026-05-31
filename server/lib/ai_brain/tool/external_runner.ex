defmodule AIBrain.Tool.ExternalRunner do
  @moduledoc """
  Executes external Skill handlers (shell scripts, etc.).
  The handler manages its own external DB — the framework does not intervene.
  """

  require Logger

  @spec run(handler_spec :: map(), input :: map(), ctx :: map()) ::
          {:ok, String.t()} | {:error, String.t()}
  def run(%{"type" => "shell", "path" => path, "action" => action}, input, ctx) do
    env = build_env(input, ctx)

    case System.cmd(path, String.split(action), env: env, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {output, code} ->
        Logger.warning("ExternalRunner: #{path} exited #{code}: #{String.slice(output, 0, 200)}")
        {:error, "Handler exited #{code}: #{String.trim(output)}"}
    end
  rescue
    e ->
      {:error, "Handler error: #{Exception.message(e)}"}
  end

  def run(%{"type" => type}, _input, _ctx) do
    {:error, "Unknown handler type: #{type}"}
  end

  defp build_env(input, ctx) do
    base = [
      {"SKILL_SESSION_ID", to_string(Map.get(ctx, :session_id, ""))},
      {"SKILL_INPUT", Jason.encode!(input)}
    ]

    base
  end
end
