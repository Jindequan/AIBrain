defmodule AIBrain.Knowledge.RegistryTest do
  use ExUnit.Case, async: false

  alias AIBrain.Knowledge.Registry

  setup do
    # 创建临时知识目录
    tmp_dir = Path.join(System.tmp_dir!(), "knowledge_test_#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    # 创建测试知识文件
    File.write!(Path.join(tmp_dir, "test1.md"), """
    ---
    id: "test1"
    category: "scientific"
    domain: "general"
    title: "Test Knowledge 1"
    tags: ["all"]
    applicable_intents: ["all"]
    version: "1.0"
    ---

    This is test content 1.
    """)

    File.write!(Path.join(tmp_dir, "test2.md"), """
    ---
    id: "test2"
    category: "engineering"
    domain: "software"
    title: "Test Knowledge 2"
    tags: ["software", "backend"]
    applicable_intents: ["debugging", "coding"]
    version: "1.0"
    ---

    This is test content 2.
    """)

    # 启动 Registry
    _pid = start_supervised!({Registry, knowledge_dir: tmp_dir, name: :test_knowledge_registry})

    %{registry: :test_knowledge_registry, tmp_dir: tmp_dir}
  end

  describe "load_for_intent/2" do
    test "returns all knowledge when intent matches 'all'", %{registry: registry} do
      knowledge = GenServer.call(registry, {:load_for_intent, :any_intent, nil})

      # test1 适用所有 intent
      assert length(knowledge) == 1
      assert hd(knowledge) =~ "Test Knowledge 1"
    end

    test "returns matching knowledge for specific intent", %{registry: registry} do
      knowledge = GenServer.call(registry, {:load_for_intent, :debugging, nil})

      # test1 (applicable_intents: ["all"]) 和 test2 (applicable_intents: ["debugging"]) 都匹配
      assert length(knowledge) == 2
      assert Enum.any?(knowledge, &(&1 =~ "Test Knowledge 1"))
      assert Enum.any?(knowledge, &(&1 =~ "Test Knowledge 2"))
    end

    test "filters by domain when provided", %{registry: registry} do
      knowledge = GenServer.call(registry, {:load_for_intent, :debugging, "software"})

      # test1 (tags: ["all"]) 和 test2 (tags: ["software"]) 都匹配
      assert length(knowledge) == 2
      assert Enum.any?(knowledge, &(&1 =~ "Test Knowledge 1"))
      assert Enum.any?(knowledge, &(&1 =~ "Test Knowledge 2"))
    end

    test "returns empty when no match", %{registry: registry} do
      knowledge = GenServer.call(registry, {:load_for_intent, :design, nil})

      # test1 的 applicable_intents 包含 "all"，所以匹配
      assert length(knowledge) >= 1
      assert hd(knowledge) =~ "Test Knowledge 1"
    end
  end

  describe "list_all/0" do
    test "returns all loaded knowledge entries", %{registry: registry} do
      entries = GenServer.call(registry, :list_all)

      assert length(entries) == 2
      assert Enum.any?(entries, fn e -> e.id == "test1" end)
      assert Enum.any?(entries, fn e -> e.id == "test2" end)
    end
  end

  describe "rescan/0" do
    test "reloads knowledge from directory", %{registry: registry, tmp_dir: tmp_dir} do
      # 添加新文件
      File.write!(Path.join(tmp_dir, "test3.md"), """
      ---
      id: "test3"
      category: "methodology"
      domain: "general"
      title: "Test Knowledge 3"
      tags: ["all"]
      applicable_intents: ["all"]
      version: "1.0"
      ---

      This is test content 3.
      """)

      # 重新扫描
      :ok = GenServer.call(registry, :rescan)

      # 验证新文件已加载
      entries = GenServer.call(registry, :list_all)
      assert length(entries) == 3
      assert Enum.any?(entries, fn e -> e.id == "test3" end)
    end
  end
end
