defmodule AIBrain.Channel.Responders.TaskResponder do
  @moduledoc """
  Builds channel-friendly replies for task queries.
  """

  alias AIBrain.Channel.Reply

  def build_status(task) do
    status = field(task, :status)
    description = field(task, :description) || ""
    exit_code = field(task, :exit_code)
    text = "Task #{field(task, :id)}: #{status}"
    text = if description != "", do: text <> " - #{description}", else: text
    text = if exit_code, do: text <> " (exit: #{exit_code})", else: text
    Reply.build(:task_status, text, %{task_id: field(task, :id), status: status})
  end

  def build_list(tasks) do
    lines = ["Tasks (#{length(tasks)} total)" | Enum.map(tasks, &render_task_line/1)]
    Reply.build(:task_list, Enum.join(lines, "\n"))
  end

  def build_output(task, output) do
    truncated =
      if byte_size(output) > 4096 do
        binary_part(output, byte_size(output) - 4096, 4096) |> String.trim()
      else
        output
      end

    text = "Output of #{field(task, :id)}:\n#{truncated}"
    Reply.build(:task_output, text, %{task_id: field(task, :id)})
  end

  defp render_task_line(task) do
    "  [#{field(task, :status)}] #{field(task, :id)} - #{field(task, :description) || ""}"
  end

  defp field(task, key) when is_map(task), do: Map.get(task, key) || Map.get(task, to_string(key))
end
