defmodule AIBrain.Planning.Agent do
  @moduledoc """
  Interactive Planning Agent that runs as an Engine.Transaction.

  Starts a :plan type transaction with the planning tools. Handles
  tool call results by writing them to the database (create Goal, Task).
  Captures ask_question calls through PlanSink for the caller to handle.
  """

  require Logger

  alias AIBrain.Engine.{Overseer, Transaction}
  alias AIBrain.Engine.ResultSink.PlanSink
  alias AIBrain.Data.{Goals, Tasks}

  @doc """
  Start a planning session.

  Returns `{:ok, plan_result}` on completion, or `{:error, reason}`.
  """
  def run(user_request, opts \\ []) do
    session_id = "plan-#{System.unique_integer([:positive])}"

    messages = [
      %{role: "user", content: user_request}
    ]

    tools = AIBrain.Prompts.planning_agent_tools()

    tx =
      Transaction.new(:plan, session_id, messages, tools,
        max_turns: Keyword.get(opts, :max_turns, 50)
      )

    ctx = %{
      router: Keyword.get(opts, :router, AIBrain.Provider.Router),
      executor: Keyword.get(opts, :executor, AIBrain.Tool.Executor),
      system: AIBrain.Prompts.planning_agent_system(),
      model: Keyword.get(opts, :model),
      http_client: Keyword.get(opts, :http_client),
      on_event: Keyword.get(opts, :on_event, fn _ -> :ok end),
      authorize_tool: fn tu -> {:allow, tu} end,
      caller: self(),
      caller_chain: [self() | Process.get(:"$callers", [])],
      context: %{plan_session_id: session_id}
    }

    case Overseer.start_transaction(
           Keyword.get(opts, :overseer, Overseer),
           tx,
           PlanSink,
           ctx
         ) do
      {:ok, executor_pid} ->
        await_results(session_id, executor_pid, Keyword.get(opts, :timeout, 300_000))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp await_results(session_id, executor_pid, timeout) do
    receive do
      {:transaction_complete, ^session_id, result} ->
        case result do
          {:ok, text, _messages} ->
            {:ok, %{session_id: session_id, summary: text}}

          error ->
            error
        end

      {:ask_question, question, from} ->
        PlanSink.store_question(session_id, question)
        send(from, {:answer, nil})
        await_results(session_id, executor_pid, timeout)
    after
      timeout ->
        Overseer.cancel(Overseer, executor_pid)
        {:error, :timeout}
    end
  end

  @doc """
  Process a tool result from the Planning Agent's transaction.

  Called by the tool executor callback. Handles each planning tool:
  - create_goal: insert Goal record, return goal_id
  - add_task: insert Task record, return task_id
  - complete_plan: no-op, signals completion
  - ask_question: forwards to caller
  """
  def handle_tool_call(tool_call, context) do
    name = tool_call["name"]
    args = tool_call["input"] || %{}

    case name do
      "create_goal" ->
        attrs = %{
          title: args["title"],
          description: args["description"],
          priority: args["priority"] || 3
        }

        case Goals.create(attrs) do
          {:ok, goal} ->
            {:ok, %{id: goal.id, title: goal.title}}

          {:error, reason} ->
            {:error, "Failed to create goal: #{inspect(reason)}"}
        end

      "add_task" ->
        attrs = %{
          goal_id: args["goal_id"],
          title: args["title"],
          description: args["description"],
          priority: args["priority"] || 3,
          depends_on: args["depends_on"] || []
        }

        case Tasks.create_task(attrs) do
          {:ok, task} ->
            AIBrain.Task.Dispatcher.notify_pending(task.id)
            {:ok, %{id: task.id, title: task.title, depends_on: task.depends_on}}

          {:error, reason} ->
            {:error, "Failed to create task: #{inspect(reason)}"}
        end

      "complete_plan" ->
        {:ok, %{summary: args["summary"] || "Plan completed"}}

      "ask_question" ->
        question = args["question"]
        {:ask, question, context}

      _ ->
        {:error, "Unknown tool: #{name}"}
    end
  end
end
