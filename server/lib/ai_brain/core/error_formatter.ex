defmodule AIBrain.Core.ErrorFormatter do
  @moduledoc """
  Centralized error formatting for the agent runtime.

  All error-to-message translations should go through this module
  to prevent duplication and ensure consistency across WebSocket,
  HTTP API, and channel adapters.
  """

  @doc """
  Format an error reason into a human-readable string.

  Returns a tuple of `{english_message, chinese_message}` so callers
  can pick the appropriate locale.
  """
  @spec format(term()) :: {String.t(), String.t()}
  def format(:max_turns_exceeded),
    do: {"Conversation reached maximum turns", "对话达到最大轮次限制"}

  def format(:max_retries_exceeded),
    do: {"Conversation reached maximum retries", "对话达到最大重试次数"}

  def format(:all_providers_unavailable),
    do: {"AI service is temporarily unavailable. Please try again later.", "AI 服务暂时不可用，请稍后重试"}

  def format(:transport_error),
    do: {"AI service connection failed. Please try again later.", "与 AI 服务通信失败，请稍后重试"}

  def format(:timeout),
    do: {"Request timed out", "请求超时"}

  def format(:wall_time_exceeded),
    do: {"Conversation exceeded maximum duration", "对话超过最大时长"}

  def format(:cancelled),
    do: {"Request was cancelled", "请求已取消"}

  def format(:rate_limited),
    do: {"AI service is busy. Please try again later.", "AI 服务繁忙，请稍后重试"}

  def format({:provider_error, msg}) when is_binary(msg),
    do: {msg, msg}

  def format({:provider_error, status}) when is_integer(status),
    do: {"Model server returned error #{status}", "模型服务器返回错误 #{status}"}

  def format({:blocked, %{reason: reason}}) when is_binary(reason),
    do: {reason, reason}

  def format({:blocked, reason}) when is_binary(reason),
    do: {reason, reason}

  def format({:exception, msg, _mod}) when is_binary(msg),
    do: {"Internal error: #{msg}", "内部错误：#{msg}"}

  def format({:permission_required, reason}),
    do: {"Authorization required — #{reason}", "需要授权 — #{reason}"}

  def format({:error, reason, _detail}),
    do: format(reason)

  def format({:error, reason}),
    do: format(reason)

  def format({:crash, msg}) when is_binary(msg),
    do: {"Internal error: #{msg}", "内部错误：#{msg}"}

  def format({:worker_crash, _reason}),
    do: {"Task worker failed. Please try again later.", "任务执行进程失败，请稍后重试"}

  def format(msg) when is_binary(msg),
    do: {msg, msg}

  def format(other) when is_atom(other),
    do: {humanize_atom(other), humanize_atom(other)}

  def format(other),
    do: {"Internal error: #{inspect(other)}", "内部错误：#{inspect(other)}"}

  @doc """
  Format an error in English (default for API/WebSocket responses).
  """
  @spec format_en(term()) :: String.t()
  def format_en(reason), do: elem(format(reason), 0)

  @doc """
  Format an error in Chinese (for channel adapter messages).
  """
  @spec format_zh(term()) :: String.t()
  def format_zh(reason), do: elem(format(reason), 1)

  defp humanize_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
