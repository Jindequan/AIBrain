defmodule AIBrain.Data.Interactions do
  @moduledoc """
  CRUD for interaction records — persisted lifecycle of user-facing decisions.
  """

  import Ecto.Query

  alias AIBrain.Repo
  alias AIBrain.Data.Interaction

  @doc "Create an interaction."
  def create(attrs) when is_map(attrs) do
    %Interaction{}
    |> Interaction.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get an interaction by ID."
  def get(id) do
    Repo.get(Interaction, id)
  end

  @doc "List interactions with optional filters."
  def list(opts \\ []) do
    query = from(i in Interaction, order_by: [desc: i.inserted_at])

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        s -> from(i in query, where: i.status == ^s)
      end

    query =
      case Keyword.get(opts, :type) do
        nil -> query
        t -> from(i in query, where: i.type == ^t)
      end

    query =
      case Keyword.get(opts, :session_id) do
        nil ->
          query

        session_id ->
          from(i in query,
            where: fragment("json_extract(context, '$.session_id') = ?", ^session_id)
          )
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        n -> from(i in query, limit: ^n)
      end

    Repo.all(query)
  end

  @doc "Update interaction status and result."
  def resolve(id, result, resolved_by, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.transaction(fn ->
      case Repo.get(Interaction, id) do
        nil ->
          Repo.rollback(:not_found)

        %{status: status} when status in ~w(resolved expired cancelled) ->
          Repo.rollback(:wrong_status)

        interaction ->
          changes = %{
            status: "resolved",
            result: result,
            resolved_by: resolved_by,
            resolved_at: now
          }

          changes =
            case Keyword.get(opts, :proxy_trail) do
              trail when is_list(trail) -> Map.put(changes, :proxy_trail, trail)
              _ -> changes
            end

          interaction
          |> Ecto.Changeset.change(changes)
          |> Repo.update!()
      end
    end)
  end

  @doc """
  Claim a pending interaction for proxy processing.
  Atomic CAS: only succeeds if status is "pending".
  Returns {:ok, interaction} or {:error, :wrong_status | :not_found}.
  """
  def claim_for_proxy(id) do
    Repo.transaction(fn ->
      case Repo.get(Interaction, id) do
        nil ->
          Repo.rollback(:not_found)

        %{status: "pending"} = i ->
          i |> Ecto.Changeset.change(status: "proxy_running") |> Repo.update!()

        _ ->
          Repo.rollback(:wrong_status)
      end
    end)
  end

  @doc """
  Mark an interaction as needing manual user handling.
  Caller must pass the current interaction (pre-read) to check its status.
  """
  def mark_need_manual(id, opts \\ []) do
    proxy_trail = opts[:proxy_trail] || []
    reason = opts[:reason]

    Repo.transaction(fn ->
      case Repo.get(Interaction, id) do
        nil ->
          Repo.rollback(:not_found)

        %{status: s} = i when s in ~w(pending proxy_running need_manual) ->
          changes = %{status: "need_manual", proxy_trail: proxy_trail}
          changes = if reason, do: Map.put(changes, :result, %{reason: reason}), else: changes
          i |> Ecto.Changeset.change(changes) |> Repo.update!()

        _ ->
          Repo.rollback(:wrong_status)
      end
    end)
  end

  @doc "Mark as escalated (proxy couldn't decide)."
  def escalate(id, proxy_trail) do
    Repo.get(Interaction, id)
    |> case do
      nil ->
        {:error, :not_found}

      interaction ->
        interaction
        |> Ecto.Changeset.change(%{
          status: "escalated",
          proxy_trail: proxy_trail
        })
        |> Repo.update()
    end
  end

  @doc "Find pending interactions that have expired."
  def expired do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Repo.all(
      from(i in Interaction,
        where: i.status in ~w(pending proxy_running need_manual),
        where: not is_nil(i.expires_at) and i.expires_at < ^now
      )
    )
  end

  @doc "Get interactions by session_id (stored in context JSON)."
  def by_session(session_id) do
    Repo.all(
      from(i in Interaction,
        where: fragment("json_extract(context, '$.session_id') = ?", ^session_id),
        order_by: [desc: i.inserted_at]
      )
    )
  end

  @doc "Get interactions for a session, formatted as a user-readable chain."
  def chain_for_session(session_id) do
    by_session(session_id)
    |> Enum.map(fn i ->
      %{
        id: i.id,
        type: i.type,
        status: i.status,
        title: i.schema_data["title"] || i.schema_data[:title],
        prompt: i.schema_data["prompt"] || i.schema_data[:prompt],
        result: i.result,
        proxy_trail: i.proxy_trail,
        resolved_by: i.resolved_by,
        resolved_at: i.resolved_at
      }
    end)
  end

  @doc """
  Mark an interaction as expired. Only applies to non-terminal statuses.
  Returns {:ok, interaction} or {:error, reason}.
  """
  def expire(id) do
    Repo.get(Interaction, id)
    |> case do
      nil ->
        {:error, :not_found}

      %{status: s} = i when s in ~w(pending proxy_running need_manual) ->
        i
        |> Ecto.Changeset.change(%{
          status: "expired",
          result: %{reason: "expired"}
        })
        |> Repo.update()

      _ ->
        {:error, :wrong_status}
    end
  end

  @doc """
  Record a proxy decision in the interaction's audit trail.
  Atomically appends the entry to proxy_trail and optionally updates status.

  Entry should be a map with at least `:step`, and typically includes
  `:action`, `:reasoning`, and `:confidence`.
  """
  def record_proxy_decision(id, entry, opts \\ []) do
    Repo.transaction(fn ->
      case Repo.get(Interaction, id) do
        nil ->
          Repo.rollback(:not_found)

        i ->
          trail = (i.proxy_trail || []) ++ [normalize_trail_entry(entry)]
          changes = %{proxy_trail: trail}

          changes =
            case Keyword.get(opts, :status) do
              nil -> changes
              s -> Map.put(changes, :status, s)
            end

          i |> Ecto.Changeset.change(changes) |> Repo.update!()
      end
    end)
  end

  defp normalize_trail_entry(entry) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    entry
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put_new("recorded_at", now)
  end

  @doc "Count interactions by status, used for monitoring."
  def count_by_status(status) when is_binary(status) do
    Repo.aggregate(
      from(i in Interaction, where: i.status == ^status),
      :count,
      :id
    )
  end
end
