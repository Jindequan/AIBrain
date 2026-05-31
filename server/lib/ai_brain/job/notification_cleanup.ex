defmodule AIBrain.Job.NotificationCleanup do
  @moduledoc """
  定期清理任务，清理僵尸 notification_queue 记录。

  清理规则：
  - 状态为 "delivering" 且 scheduled_at 超过 24 小时的记录
  - 这些记录可能是由于 deliver() 崩溃后未恢复导致的
  - 清理时将其状态改为 "pending"，以便重新投递
  """

  use GenServer
  require Logger

  alias AIBrain.Repo

  # 每小时运行一次
  @cleanup_interval 3600_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    # 启动后延迟1分钟再执行首次清理，避免启动时竞争
    Process.send_after(self(), :cleanup, 60_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("NotificationCleanup: running cleanup")

    try do
      cleanup_stale_items()
    rescue
      e ->
        Logger.error("NotificationCleanup: cleanup failed: #{Exception.message(e)}")
    end

    # 安排下一次清理
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:noreply, state}
  end

  defp cleanup_stale_items do
    # 查询状态为 "delivering" 且 scheduled_at 超过 24 小时的记录
    cutoff_time = DateTime.add(DateTime.utc_now(), -24, :hour)

    {_, result} =
      Repo.query(
        """
          UPDATE notification_queue
          SET status = 'pending',
              scheduled_at = datetime('now'),
              retry_count = 0,
              last_error = 'status_reset_after_24h'
          WHERE status = 'delivering'
            AND scheduled_at < ?
          RETURNING id
        """,
        [DateTime.to_iso8601(cutoff_time)]
      )

    cleaned_count = if result.rows == [], do: 0, else: result.num_rows

    if cleaned_count > 0 do
      Logger.info("NotificationCleanup: reset #{cleaned_count} stale items to pending")
    end
  end
end
