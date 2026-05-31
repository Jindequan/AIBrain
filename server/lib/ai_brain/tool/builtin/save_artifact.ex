defmodule AIBrain.Tool.Builtin.SaveArtifact do
  @moduledoc """
  Declare a deliverable from the current task.

  This is NOT called for every file write or bash command. It's called when the AI
  identifies a meaningful deliverable — something the user asked for and actually
  received: a project directory, a single file, a generated image, a document, a URL,
  or a text summary.

  Examples:
    - "I created a React project at /code/myapp" → kind: "directory", uri: "/code/myapp"
    - "Here's the Python script" → kind: "file", uri: "/code/spider.py"
    - "Generated the image" → kind: "image", uri: "/output/chart.png"
    - "Deployed to" → kind: "url", uri: "https://myapp.example.com"
    - "Summary of the refactoring" → kind: "note", content: "..."
    - "The design document" → kind: "document", uri: "/docs/design.md"

  Rules:
    - Call ONCE per distinct deliverable, not per file.
    - For a project with 5000 files, declare ONE artifact with kind: "directory".
    - Use "note" kind for text summaries that don't map to a file.
    - Always provide a descriptive title.
  """

  @behaviour AIBrain.Tool.Behaviour

  alias AIBrain.Data.Artifacts

  def name, do: "save_artifact"

  def description do
    "Declare a deliverable from the current task. Call once per distinct deliverable (e.g. one per project directory, not one per file)."
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "title" => %{
          "type" => "string",
          "description" => "Human-readable name of the deliverable"
        },
        "kind" => %{
          "type" => "string",
          "enum" => AIBrain.Data.Artifact.valid_kinds(),
          "description" => ~s[Deliverable type:
            "directory" — a project or folder (e.g. "React app at /code/myapp")
            "file" — a single file (e.g. "spider.py")
            "image" — a generated image
            "url" — an external link (e.g. deployed URL, shared doc)
            "note" — a text summary or insight, not tied to a file
            "document" — a document file (PDF, Markdown, etc.)
            "code" — an inline code snippet]
        },
        "uri" => %{
          "type" => "string",
          "description" =>
            "File path, directory path, or URL. Required for file/directory/image/url/document kinds. Omit for 'note' kind."
        },
        "description" => %{
          "type" => "string",
          "description" => "Brief description of what this deliverable contains or accomplishes"
        },
        "content" => %{
          "type" => "string",
          "description" => "Inline content, only used for 'note' or 'code' kinds"
        },
        "metadata" => %{
          "type" => "object",
          "description" =>
            "Optional extra info, e.g. {\"file_count\": 42, \"language\": \"python\"}"
        }
      },
      "required" => ["title", "kind"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :unknown

  def execute(args, context) do
    kind = args["kind"]

    # For kinds that reference files/dirs/URLs, uri is required
    if kind in ["file", "directory", "image", "url", "document"] and
         (is_nil(args["uri"]) or args["uri"] == "") do
      {:error, "uri is required for kind '#{kind}'"}
    else
      run_id = context[:run_id]

      attrs = %{
        run_id: run_id,
        kind: kind,
        title: args["title"],
        description: args["description"],
        uri: args["uri"],
        content: args["content"],
        metadata: args["metadata"] || %{}
      }

      # Drop nil values
      attrs = Enum.filter(attrs, fn {_k, v} -> v != nil end) |> Map.new()

      case Artifacts.create(attrs) do
        {:ok, artifact} ->
          {:ok, "Deliverable saved: #{artifact.title} (#{artifact.kind})"}

        {:error, reason} ->
          {:error, "Failed to save deliverable: #{reason}"}
      end
    end
  end
end
