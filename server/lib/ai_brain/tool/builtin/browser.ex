defmodule AIBrain.Tool.Builtin.Browser do
  @behaviour AIBrain.Tool.Behaviour

  @impl true
  def name, do: "browser"

  @impl true
  def description,
    do:
      "Control a web browser: screenshots, text extraction, form filling, and clicking. Requires Node.js and Puppeteer."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["screenshot", "extract", "click", "fill"],
          "description" => "Action to perform"
        },
        "url" => %{"type" => "string", "description" => "Target URL"},
        "selector" => %{
          "type" => "string",
          "description" => "CSS selector (optional for screenshot/extract)"
        },
        "fields" => %{
          "type" => "object",
          "description" => "Form fields as {selector: value} (for fill action)",
          "additionalProperties" => %{"type" => "string"}
        }
      },
      "required" => ["action", "url"]
    }
  end

  @impl true
  def read_only?, do: false

  @impl true
  def risk_category, do: :network

  @impl true
  def execute(%{"action" => action, "url" => url} = args, _context) do
    selector = Map.get(args, "selector")
    opts = if selector, do: [selector: selector], else: []

    result =
      case action do
        "screenshot" ->
          AIBrain.Automation.Browser.screenshot(url, opts)

        "extract" ->
          AIBrain.Automation.Browser.extract_text(url, opts)

        "click" ->
          AIBrain.Automation.Browser.click(url, selector)

        "fill" ->
          fields = Map.get(args, "fields", %{})
          AIBrain.Automation.Browser.fill_form(url, fields)

        other ->
          {:error, "Unknown action: #{other}. Use: screenshot, extract, click, or fill"}
      end

    case result do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(%{} = args, _context) do
    {:error, "Missing required parameters: action and url. Got: #{inspect(args)}"}
  end
end
