defmodule AIBrain.Knowledge.Registry do
  @moduledoc """
  知识库注册表：管理所有知识条目

  从 `priv/knowledge/` 目录加载知识文件
  """

  use GenServer
  require Logger

  alias AIBrain.Knowledge.Base

  # ── Client API ──

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  为特定意图和领域加载相关知识

  ## 参数
    * intent_type - 意图类型（atom 或 string）
    * domain - 可选的领域过滤

  ## 返回
    格式化好的提示词片段列表
  """
  def load_for_intent(intent_type, domain \\ nil) do
    GenServer.call(__MODULE__, {:load_for_intent, intent_type, domain})
  end

  @doc "获取所有知识条目"
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc "强制重新扫描知识目录"
  def rescan do
    GenServer.call(__MODULE__, :rescan)
  end

  # ── Server Callbacks ──

  @impl true
  def init(opts) do
    knowledge_dir = Keyword.get(opts, :knowledge_dir, default_knowledge_dir())

    state = %{
      knowledge_dir: knowledge_dir,
      entries: [],
      last_scan: nil
    }

    {:ok, state, {:continue, :scan}}
  end

  @impl true
  def handle_continue(:scan, state) do
    entries = scan_knowledge_directory(state.knowledge_dir)

    Logger.info(
      "Knowledge.Registry: scanned #{length(entries)} entries from #{state.knowledge_dir}"
    )

    {:noreply, %{state | entries: entries, last_scan: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:load_for_intent, intent_type, domain}, _from, state) do
    relevant_entries =
      state.entries
      |> Enum.filter(&Base.applicable?(&1, intent_type, domain))
      |> Enum.map(&Base.format_for_prompt/1)

    {:reply, relevant_entries, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    {:reply, state.entries, state}
  end

  @impl true
  def handle_call(:rescan, _from, state) do
    entries = scan_knowledge_directory(state.knowledge_dir)

    Logger.info("Knowledge.Registry: rescanned #{length(entries)} entries")

    {:reply, :ok, %{state | entries: entries, last_scan: DateTime.utc_now()}}
  end

  # ── Private Helpers ──

  defp default_knowledge_dir do
    Path.join([:code.priv_dir(:ai_brain), "knowledge"])
  end

  defp scan_knowledge_directory(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(fn file ->
        path = Path.join(dir, file)

        try do
          Base.from_file(path)
        rescue
          e ->
            Logger.warning("Failed to load knowledge from #{file}: #{inspect(e)}")
            nil
        end
      end)
      |> Enum.filter(& &1)
    else
      Logger.warning("Knowledge directory not found: #{dir}")
      []
    end
  end
end
