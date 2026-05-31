defmodule AIBrain.Tool.Builtin.Email do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Email tool — thin adapter that delegates all logic to Business.Email.

  This tool should ONLY contain:
  1. Tool.Behaviour callbacks (name, description, input_schema, etc.)
  2. Argument validation
  3. Delegation to the Business layer
  """

  alias AIBrain.Business.Email

  def name, do: "email"

  def description,
    do:
      "Manage email: read inbox, send, search, reply, mark read, archive. Supports Gmail, Outlook, and IMAP."

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["send", "read_inbox", "search", "reply", "mark_read", "archive"],
          "description" => "Action to perform"
        },
        "to" => %{"type" => "string", "description" => "Recipient email (for send/reply)"},
        "subject" => %{"type" => "string", "description" => "Email subject"},
        "body" => %{"type" => "string", "description" => "Email body (plain text or HTML)"},
        "query" => %{
          "type" => "string",
          "description" => "Gmail search query (for search action)"
        },
        "message_id" => %{
          "type" => "string",
          "description" => "Message ID to reply to / mark read / archive"
        },
        "max_results" => %{
          "type" => "integer",
          "description" => "Max emails to return (default 10)"
        }
      },
      "required" => ["action"]
    }
  end

  def read_only?, do: false
  def risk_category, do: :network

  # -- Dispatch — thin delegation to Business layer --

  def execute(%{"action" => "send"} = args, _context) do
    cond do
      !args["to"] -> {:error, "Missing required: to"}
      !args["subject"] -> {:error, "Missing required: subject"}
      !args["body"] -> {:error, "Missing required: body"}
      true -> Email.send(args["to"], args["subject"], args["body"])
    end
  end

  def execute(%{"action" => "read_inbox"} = args, _context) do
    Email.read_inbox(args["max_results"], args["query"])
  end

  def execute(%{"action" => "search"} = args, _context) do
    if !args["query"] do
      {:error, "Missing required: query"}
    else
      Email.search(args["query"], args["max_results"])
    end
  end

  def execute(%{"action" => "reply"} = args, _context) do
    cond do
      !args["message_id"] -> {:error, "Missing required: message_id"}
      !args["body"] -> {:error, "Missing required: body"}
      true -> Email.reply(args["message_id"], args["body"], args)
    end
  end

  def execute(%{"action" => "mark_read"} = args, _context) do
    if !args["message_id"] do
      {:error, "Missing required: message_id"}
    else
      Email.mark_read(args["message_id"])
    end
  end

  def execute(%{"action" => "archive"} = args, _context) do
    if !args["message_id"] do
      {:error, "Missing required: message_id"}
    else
      Email.archive(args["message_id"])
    end
  end

  def execute(%{}, _),
    do: {:error, "Action must be: send, read_inbox, search, reply, mark_read, archive"}
end
