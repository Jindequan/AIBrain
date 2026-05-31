defmodule AIBrain.AgentRuntime.RunRequest do
  @moduledoc """
  Normalized request to start an agent run.

  Every entrypoint should eventually build this struct. It keeps task category
  open-ended: behavior is controlled by mode/policy/capabilities, not by a
  hard-coded task type enum.
  """

  @enforce_keys [:source_type, :objective]
  defstruct [
    :id,
    :source_type,
    :source_id,
    :objective,
    :title,
    :mode,
    :autonomy_level,
    :session_id,
    :thread_id,
    :goal_id,
    :task_id,
    :schedule_id,
    :workspace_path,
    :parent_run_id,
    :model,
    messages: [],
    context_refs: [],
    metadata: %{},
    opts: []
  ]

  @source_types ~w(chat session task goal schedule manual webhook system)
  @modes ~w(interactive background scheduled goal_tick manual plan)

  def source_types, do: @source_types
  def modes, do: @modes

  def new(attrs) when is_map(attrs) do
    attrs = atomize(attrs)

    request =
      struct(__MODULE__, %{
        id: attrs[:id],
        source_type: to_string(attrs[:source_type] || "manual"),
        source_id: attrs[:source_id],
        objective: attrs[:objective] || infer_objective(attrs[:messages]),
        title: attrs[:title],
        mode: to_string(attrs[:mode] || "interactive"),
        autonomy_level: attrs[:autonomy_level] || 0,
        session_id: attrs[:session_id],
        thread_id: attrs[:thread_id],
        goal_id: attrs[:goal_id],
        task_id: attrs[:task_id],
        schedule_id: attrs[:schedule_id],
        workspace_path: attrs[:workspace_path],
        parent_run_id: attrs[:parent_run_id],
        model: attrs[:model],
        messages: attrs[:messages] || [],
        context_refs: attrs[:context_refs] || [],
        metadata: attrs[:metadata] || %{},
        opts: attrs[:opts] || []
      })

    validate(request)
  end

  defp validate(%__MODULE__{source_type: source_type})
       when source_type not in @source_types do
    {:error, {:invalid_source_type, source_type}}
  end

  defp validate(%__MODULE__{mode: mode}) when mode not in @modes do
    {:error, {:invalid_mode, mode}}
  end

  defp validate(%__MODULE__{objective: objective})
       when not is_binary(objective) or objective == "" do
    {:error, :objective_required}
  end

  defp validate(%__MODULE__{} = request), do: {:ok, request}

  def context_refs(%__MODULE__{} = request) do
    request.context_refs
    |> Enum.map(&normalize_ref/1)
    |> add_ref(:thread, request.thread_id || request.session_id, "primary")
    |> add_ref(:session, request.session_id, "related")
    |> add_ref(:goal, request.goal_id, "parent")
    |> add_ref(:task, request.task_id, "primary")
    |> add_ref(:schedule, request.schedule_id, "trigger")
    |> add_ref(:workspace, request.workspace_path, "related")
    |> Enum.uniq_by(fn ref -> {ref.ref_type, ref.ref_id, ref.role} end)
  end

  defp add_ref(refs, _type, nil, _role), do: refs
  defp add_ref(refs, _type, "", _role), do: refs

  defp add_ref(refs, type, id, role) do
    [%{ref_type: Atom.to_string(type), ref_id: id, role: role, metadata: %{}} | refs]
  end

  defp normalize_ref(ref) when is_map(ref) do
    %{
      ref_type: to_string(ref[:ref_type] || ref["ref_type"] || ref[:type] || ref["type"]),
      ref_id: ref[:ref_id] || ref["ref_id"] || ref[:id] || ref["id"],
      role: to_string(ref[:role] || ref["role"] || "related"),
      metadata: ref[:metadata] || ref["metadata"] || %{}
    }
  end

  defp infer_objective(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "user", content: content} when is_binary(content) -> content
      %{"role" => "user", "content" => content} when is_binary(content) -> content
      _ -> nil
    end)
  end

  defp infer_objective(_), do: nil

  defp atomize(map) do
    allowed =
      ~w(id source_type source_id objective title mode autonomy_level session_id thread_id goal_id task_id schedule_id workspace_path parent_run_id messages context_refs metadata opts)
      |> Map.new(&{&1, String.to_atom(&1)})

    Map.new(map, fn
      {k, v} when is_binary(k) -> {Map.get(allowed, k, k), v}
      pair -> pair
    end)
  end
end
