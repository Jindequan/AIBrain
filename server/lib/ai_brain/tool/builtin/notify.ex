defmodule AIBrain.Tool.Builtin.Notify do
  @behaviour AIBrain.Tool.Behaviour

  @impl true
  def name, do: "notify"

  @impl true
  def description, do: "Send a desktop notification to the user"

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "title" => %{"type" => "string", "description" => "Notification title"},
        "message" => %{"type" => "string", "description" => "Notification body text"},
        "sound" => %{
          "type" => "string",
          "enum" => ["default", "alert", "none"],
          "description" => "Notification sound name"
        }
      },
      "required" => ["title", "message"]
    }
  end

  @impl true
  def read_only?, do: false

  @impl true
  def risk_category, do: :workspace_write

  @impl true
  def available? do
    case :os.type() do
      {:unix, :darwin} -> System.find_executable("osascript") != nil
      {:unix, :linux} -> System.find_executable("notify-send") != nil
      _ -> false
    end
  end

  @impl true
  def execute(%{"title" => title, "message" => message} = params, _context) do
    sound = Map.get(params, "sound", "default")

    case :os.type() do
      {:unix, :darwin} ->
        macos_notify(title, message, sound)

      {:unix, :linux} ->
        linux_notify(title, message)

      _ ->
        {:error, "Desktop notifications are not supported on this operating system"}
    end
  end

  def execute(%{"title" => _title}, _context) do
    {:error, "Missing required field: message"}
  end

  def execute(_params, _context) do
    {:error, "Missing required fields: title and message"}
  end

  # ── macOS ───────────────────────────────────────────────────────

  defp macos_notify(title, message, sound) do
    escaped_title = escape(title)
    escaped_message = escape(message)

    script =
      ~s(display notification "#{escaped_message}" with title "#{escaped_title}" sound name "#{sound}")

    case System.cmd("osascript", ["-e", script]) do
      {"", 0} ->
        {:ok, "Notification sent: #{title}"}

      {error, code} ->
        {:error, "Notification failed (exit #{code}): #{String.trim(error)}"}
    end
  end

  # ── Linux ───────────────────────────────────────────────────────

  defp linux_notify(title, message) do
    with {:ok, _} <- System.cmd("which", ["notify-send"]) do
      case System.cmd("notify-send", [title, message]) do
        {"", 0} -> {:ok, "Notification sent: #{title}"}
        {error, code} -> {:error, "notify-send failed (exit #{code}): #{String.trim(error)}"}
      end
    else
      _ ->
        {:error, "notify-send not found. Install libnotify-bin to enable desktop notifications."}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp escape(str), do: String.replace(str, "\"", "\\\"")
end
