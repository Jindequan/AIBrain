defmodule AIBrain.Skill.Spec do
  @moduledoc """
  Codex-style skill specification.

  A skill is a directory containing one required `SKILL.md` file and optional
  `scripts/`, `references/`, `assets/`, and `agents/` resource directories.
  Only `name` and `description` are required in frontmatter. The Markdown body
  is loaded only after a skill is selected.
  """

  defstruct [
    :name,
    :description,
    :body,
    :path,
    :root_path,
    :origin,
    :source_uri,
    metadata: %{},
    status: :active,
    resources: %{scripts: [], references: [], assets: [], agents: []}
  ]

  @type origin :: :builtin | :user | :external

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          body: String.t(),
          path: String.t(),
          root_path: String.t(),
          origin: origin(),
          source_uri: String.t() | nil,
          metadata: map(),
          status: :active | :paused,
          resources: map()
        }

  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def parse(path, opts \\ []) when is_binary(path) do
    with :ok <- require_skill_filename(path),
         {:ok, content} <- read_file(path),
         {:ok, spec} <- parse_content(content, opts) do
      root_path = Path.dirname(path)

      {:ok,
       %{
         spec
         | path: path,
           root_path: root_path,
           resources: discover_resources(root_path)
       }}
    end
  end

  @spec parse_content(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def parse_content(content, opts \\ []) when is_binary(content) do
    with {:ok, frontmatter_str, body} <- split_frontmatter(content),
         {:ok, fields} <- parse_frontmatter(frontmatter_str),
         {:ok, name} <- required_field(fields, "name"),
         {:ok, description} <- required_field(fields, "description"),
         :ok <- validate_name(name) do
      {:ok,
       %__MODULE__{
         name: name,
         description: description,
         body: String.trim_trailing(body),
         path: "",
         root_path: "",
         origin: parse_origin(Keyword.get(opts, :origin) || Map.get(fields, "origin", "user")),
         source_uri: Keyword.get(opts, :source_uri) || Map.get(fields, "source_uri"),
         metadata: normalize_map(Map.get(fields, "metadata", %{})),
         status: parse_status(Map.get(fields, "status", "active"))
       }}
    end
  end

  @doc "Build the canonical `SKILL.md` content for a skill."
  def render(%__MODULE__{} = spec) do
    metadata =
      if map_size(spec.metadata || %{}) > 0 do
        "\nmetadata:\n" <>
          (spec.metadata
           |> Enum.sort_by(fn {k, _v} -> k end)
           |> Enum.map_join("", fn {k, v} -> "  #{k}: #{yaml_scalar(v)}\n" end))
      else
        ""
      end

    source =
      if is_binary(spec.source_uri) and spec.source_uri != "" do
        "\nsource_uri: #{yaml_scalar(spec.source_uri)}"
      else
        ""
      end

    status =
      if spec.status == :paused do
        "\nstatus: paused"
      else
        ""
      end

    """
    ---
    name: #{spec.name}
    description: #{yaml_scalar(spec.description)}#{status}#{source}#{metadata}
    ---

    #{String.trim_trailing(spec.body || "")}
    """
    |> String.trim_leading()
  end

  def validate_name(name) when is_binary(name) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9_-]*\z/, name) do
      :ok
    else
      {:error, "invalid skill name: use lowercase letters, numbers, hyphens, and underscores"}
    end
  end

  def validate_name(_), do: {:error, "invalid skill name"}

  defp require_skill_filename(path) do
    if Path.basename(path) == "SKILL.md" do
      :ok
    else
      {:error, "skill entrypoint must be named SKILL.md"}
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "could not read file: #{reason}"}
    end
  end

  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/s, content) do
      [_, frontmatter, body] -> {:ok, String.trim(frontmatter), body}
      nil -> {:error, "missing YAML frontmatter"}
    end
  end

  defp parse_frontmatter(frontmatter) do
    lines = String.split(frontmatter, "\n")
    parse_lines(lines, %{}, nil)
  catch
    {:parse_error, reason} -> {:error, reason}
  end

  defp parse_lines([], acc, nil), do: {:ok, acc}
  defp parse_lines([], acc, {:map, key, data}), do: {:ok, Map.put(acc, key, data)}

  defp parse_lines([line | rest], acc, nil) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_lines(rest, acc, nil)

      Regex.match?(~r/^[a-zA-Z_][\w-]*:\s*$/, trimmed) ->
        key = String.trim_trailing(trimmed, ":")
        parse_lines(rest, acc, {:map, key, %{}})

      Regex.match?(~r/^[a-zA-Z_][\w-]*:/, trimmed) ->
        {key, value} = split_key_value(trimmed)
        parse_lines(rest, Map.put(acc, key, unquote_yaml(value)), nil)

      true ->
        throw({:parse_error, "invalid frontmatter line: #{trimmed}"})
    end
  end

  defp parse_lines([line | rest], acc, {:map, key, data} = state) do
    trimmed = String.trim(line)
    indent = String.length(line) - String.length(String.trim_leading(line))

    cond do
      trimmed == "" ->
        parse_lines(rest, acc, state)

      indent > 0 and Regex.match?(~r/^[a-zA-Z_][\w-]*:/, trimmed) ->
        {sub_key, value} = split_key_value(trimmed)
        parse_lines(rest, acc, {:map, key, Map.put(data, sub_key, unquote_yaml(value))})

      true ->
        parse_lines([line | rest], Map.put(acc, key, data), nil)
    end
  end

  defp split_key_value(line) do
    case Regex.run(~r/^([a-zA-Z_][\w-]*)\s*:\s*(.*)$/, line) do
      [_, key, value] -> {key, String.trim(value)}
      nil -> throw({:parse_error, "invalid key/value line: #{line}"})
    end
  end

  defp required_field(fields, key) do
    case Map.get(fields, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "missing required field: #{key}"}
    end
  end

  defp unquote_yaml("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unquote_yaml("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unquote_yaml(other), do: other

  defp yaml_scalar(value) when is_binary(value) do
    if Regex.match?(~r/\A[a-zA-Z0-9_.:\/ -]+\z/, value) do
      value
    else
      Jason.encode!(value)
    end
  end

  defp yaml_scalar(value), do: inspect(value)

  defp parse_status("paused"), do: :paused
  defp parse_status(:paused), do: :paused
  defp parse_status(_), do: :active

  defp parse_origin("builtin"), do: :builtin
  defp parse_origin("external"), do: :external
  defp parse_origin(:builtin), do: :builtin
  defp parse_origin(:external), do: :external
  defp parse_origin(_), do: :user

  defp normalize_map(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp normalize_map(_), do: %{}

  defp discover_resources(root_path) do
    %{
      scripts: list_resource_dir(root_path, "scripts"),
      references: list_resource_dir(root_path, "references"),
      assets: list_resource_dir(root_path, "assets"),
      agents: list_resource_dir(root_path, "agents")
    }
  end

  defp list_resource_dir(root_path, dir_name) do
    dir = Path.join(root_path, dir_name)

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.sort()
    else
      []
    end
  rescue
    _ -> []
  end
end
