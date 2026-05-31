defmodule AIBrain.Tool.Builtin.ProxyControl do
  @behaviour AIBrain.Tool.Behaviour

  @moduledoc """
  Lets the agent control the Proxy system.

  Modes:
    - assist: Proxy evaluates and escalates uncertain cases to the user.
    - autonomy: Proxy decides everything. No human escalation. For unattended operation.
  """

  def name, do: "proxy_control"
  def read_only?, do: false

  def description do
    "Control the proxy: enable/disable, switch between assist and full autonomy modes. " <>
      "Use autonomy when the user says 'go to sleep' or expects unattended operation."
  end

  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["enable", "disable", "autonomy", "assist", "status"],
          "description" => "Action: enable/disable proxy, switch to autonomy/assist mode, or check status"
        }
      },
      "required" => ["action"]
    }
  end

  def execute(%{"action" => "enable"}, _ctx) do
    with {:ok, _} <- AIBrain.Data.Users.update(%{active: true}, "proxy") do
      AIBrain.Proxy.set_active(true)
      {:ok, "Proxy enabled. I'll evaluate actions and escalate uncertain cases to you."}
    else
      {:error, reason} -> {:error, "Failed to enable proxy: #{reason}"}
    end
  end

  def execute(%{"action" => "disable"}, _ctx) do
    with {:ok, _} <- AIBrain.Data.Users.update(%{active: false}, "proxy") do
      AIBrain.Proxy.set_active(false)
      {:ok, "Proxy disabled. All tool approvals will go directly to you."}
    else
      {:error, reason} -> {:error, "Failed to disable proxy: #{reason}"}
    end
  end

  def execute(%{"action" => "autonomy"}, _ctx) do
    {:ok, proxy} = AIBrain.Data.Users.get_proxy()
    meta = (proxy.metadata || %{}) |> Map.put("autonomy", true)

    with {:ok, _} <- AIBrain.Data.Users.update(%{active: true, metadata: meta}, "proxy") do
      AIBrain.Proxy.set_active(true)
      AIBrain.Proxy.set_autonomy(true)
      {:ok, "Full autonomy enabled. I will handle ALL decisions without escalating. You can sleep now."}
    else
      {:error, reason} -> {:error, "Failed: #{reason}"}
    end
  end

  def execute(%{"action" => "assist"}, _ctx) do
    {:ok, proxy} = AIBrain.Data.Users.get_proxy()
    meta = (proxy.metadata || %{}) |> Map.put("autonomy", false)

    with {:ok, _} <- AIBrain.Data.Users.update(%{metadata: meta}, "proxy") do
      AIBrain.Proxy.set_autonomy(false)
      {:ok, "Assist mode. I'll escalate uncertain decisions to you again."}
    else
      {:error, reason} -> {:error, "Failed: #{reason}"}
    end
  end

  def execute(%{"action" => "status"}, _ctx) do
    case AIBrain.Data.Users.get_proxy() do
      {:ok, %{active: true, metadata: %{"autonomy" => true}}} ->
        {:ok, "Proxy active in FULL AUTONOMY mode. All decisions are made without you."}

      {:ok, %{active: true}} ->
        {:ok, "Proxy active in ASSIST mode. Uncertain cases will be escalated to you."}

      {:ok, _} ->
        {:ok, "Proxy disabled. All approvals are sent to you."}
    end
  end

  def execute(%{}, _ctx) do
    {:error, "Missing required: action"}
  end
end
