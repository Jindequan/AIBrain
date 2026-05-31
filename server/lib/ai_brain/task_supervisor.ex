defmodule AIBrain.TaskSupervisor do
  @moduledoc """
  动态监督员的便捷接口。

  提供统一的 API 来启动受监督的任务。
  实际的 Task.Supervisor 在 Application 中启动。
  """

  @doc """
  启动一个受监督的任务，返回 Task pid
  """
  def start_child(fun) do
    Task.Supervisor.start_child(__MODULE__, fun)
  end

  @doc """
  启动一个受监督的任务，等待结果
  """
  def start_child_and_await(fun, timeout \\ 5000) do
    task = Task.Supervisor.start_child(__MODULE__, fun)
    Task.await(task, timeout)
  end
end
