defmodule AIBrain.Knowledge.Base do
  @moduledoc """
  知识系统：存储科学规范、工程方法、理论指导

  知识条目结构：
  - id: 唯一标识
  - category: 分类（scientific/engineering/methodology/theory）
  - domain: 领域（software/backend/frontend/devops等）
  - title: 标题
  - content: 内容（Markdown）
  - principles: 核心原则列表
  - examples: 示例
  - tags: 标签
  - applicable_intents: 适用的意图类型
  - version: 版本
  """

  defstruct [
    :id,
    :category,
    :domain,
    :title,
    :content,
    :principles,
    :examples,
    :tags,
    :applicable_intents,
    :version
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          category: :scientific | :engineering | :methodology | :theory,
          domain: String.t(),
          title: String.t(),
          content: String.t(),
          principles: [String.t()],
          examples: String.t(),
          tags: [String.t()],
          applicable_intents: [String.t()],
          version: String.t()
        }

  @doc """
  格式化知识条目为提示词片段
  """
  def format_for_prompt(%__MODULE__{} = knowledge) do
    """
    ## #{knowledge.title}

    #{knowledge.content}

    **核心原则：**
    #{Enum.map(knowledge.principles, &("- " <> &1)) |> Enum.join("\n")}

    #{if knowledge.examples != "" do
      "**示例：**\n#{knowledge.examples}"
    end}
    """
  end

  @doc """
  检查知识条目是否适用于给定的意图和领域
  """
  def applicable?(%__MODULE__{} = knowledge, intent_type, domain \\ nil) do
    type_match =
      intent_type in knowledge.applicable_intents or
        Enum.any?(knowledge.applicable_intents, fn applicable ->
          applicable == "all" or String.contains?(to_string(intent_type), applicable)
        end)

    domain_match =
      is_nil(domain) or
        domain in knowledge.tags or
        Enum.any?(knowledge.tags, fn tag -> tag == "all" or tag == domain end)

    type_match and domain_match
  end

  @doc """
  从文件路径加载知识条目
  """
  def from_file(path) do
    content = File.read!(path)
    {frontmatter, body} = split_frontmatter(content)

    struct(__MODULE__,
      id: frontmatter["id"],
      category: parse_category(frontmatter["category"]),
      domain: frontmatter["domain"],
      title: frontmatter["title"],
      content: body,
      principles: frontmatter["principles"] || [],
      examples: frontmatter["examples"] || "",
      tags: frontmatter["tags"] || [],
      applicable_intents: frontmatter["applicable_intents"] || [],
      version: frontmatter["version"] || "1.0"
    )
  end

  defp split_frontmatter(content) do
    # 检查是否以 --- 开头（YAML frontmatter）
    trimmed = String.trim_leading(content)

    if String.starts_with?(trimmed, "---") do
      # 移除开头的 ---
      without_first_marker = String.replace_prefix(trimmed, "---", "")
      # 找到结束的 ---
      case String.split(without_first_marker, "\n---\n", parts: 2) do
        [frontmatter, body] ->
          {parse_yaml_frontmatter(frontmatter), String.trim(body)}

        _ ->
          # 没有找到结束标记，可能是整个内容都是 frontmatter
          {%{}, String.trim(content)}
      end
    else
      # 没有 frontmatter
      {%{}, content}
    end
  end

  defp parse_yaml_frontmatter(yaml_str) do
    # 简单的 YAML 解析（生产环境应使用 YamlElixir）
    try do
      yaml_str
      |> String.split("\n")
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(fn line ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            {String.trim(key), parse_yaml_value(String.trim(value))}

          _ ->
            nil
        end
      end)
      |> Enum.filter(& &1)
      |> Map.new()
    rescue
      _ -> %{}
    end
  end

  defp parse_yaml_value(value) do
    cond do
      String.starts_with?(value, "[") and String.ends_with?(value, "]") ->
        # 数组
        inner = String.slice(value, 1, String.length(value) - 2)

        inner
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn v ->
          v = String.trim(v)

          if String.starts_with?(v, "\"") do
            String.slice(v, 1, String.length(v) - 2) |> String.trim()
          else
            v
          end
        end)

      String.starts_with?(value, "\"") ->
        # 字符串
        String.slice(value, 1, String.length(value) - 2) |> String.trim()

      true ->
        # 原始值
        value
    end
  end

  defp parse_category("scientific"), do: :scientific
  defp parse_category("engineering"), do: :engineering
  defp parse_category("methodology"), do: :methodology
  defp parse_category("theory"), do: :theory
  defp parse_category(_), do: :engineering
end
