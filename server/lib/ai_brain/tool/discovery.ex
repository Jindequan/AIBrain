defmodule AIBrain.Tool.Discovery do
  @moduledoc """
  Auto-discovers and registers built-in tools at startup.
  Provides APIs to list available tools.
  """

  @builtin_modules [
    AIBrain.Tool.Builtin.Bash,
    AIBrain.Tool.Builtin.FileRead,
    AIBrain.Tool.Builtin.FileWrite,
    AIBrain.Tool.Builtin.FileEdit,
    AIBrain.Tool.Builtin.Glob,
    AIBrain.Tool.Builtin.Grep,
    AIBrain.Tool.Builtin.WebSearch,
    AIBrain.Tool.Builtin.WebFetch,
    AIBrain.Tool.Builtin.DocRead,
    AIBrain.Tool.Builtin.Email,
    AIBrain.Tool.Builtin.Calendar,
    AIBrain.Tool.Builtin.Git,
    AIBrain.Tool.Builtin.Notify,
    AIBrain.Tool.Builtin.Clipboard,
    AIBrain.Tool.Builtin.AssistantAdmin,
    AIBrain.Tool.Builtin.GoalTaskTool,
    AIBrain.Tool.Builtin.Image,
    AIBrain.Tool.Builtin.ProxyControl,
    AIBrain.Tool.Builtin.SaveArtifact
  ]

  @doc """
  Register all built-in tools. Called during application startup.
  """
  def register_builtin_tools(registry) do
    Enum.each(@builtin_modules, fn mod ->
      AIBrain.Tool.Registry.register(registry, mod)
    end)

    :ok
  end

  @doc """
  List all registered tools with metadata.
  """
  def list_tools(registry \\ AIBrain.Tool.Registry) do
    registry
    |> AIBrain.Tool.Registry.all()
    |> Enum.map(fn mod ->
      %{
        name: mod.name(),
        description: mod.description(),
        read_only: mod.read_only?(),
        risk_category: risk_category(mod)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp risk_category(mod) do
    if function_exported?(mod, :risk_category, 0) do
      mod.risk_category()
    else
      cond do
        mod.read_only?() -> :read_only
        mod.name() == "bash" -> :shell_exec
        mod.name() in ["file_write", "file_edit"] -> :workspace_write
        true -> :unknown
      end
    end
  end
end
