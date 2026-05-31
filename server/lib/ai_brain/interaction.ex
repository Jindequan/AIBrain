defmodule AIBrain.Interaction do
  @moduledoc """
  Facade for the interaction system.

  Provides clean entry points for creating and resolving interactions.
  """

  @doc """
  Create an interaction. Returns `{:ok, interaction_id}` or `{:error, reason}`.

  ## Options
    * `:resume_token` — token for Resumer to pick up and unblock process
    * `:expires_in` — seconds until expiry (default: 300)
    * `:prompt_versions` — map of prompt version IDs used for this decision
  """
  def request(type, schema, context, opts \\ []) do
    AIBrain.Interaction.Manager.request(type, schema, context, opts)
  end

  @doc "Resolve an interaction by ID."
  def resolve(interaction_id, result, resolved_by \\ AIBrain.Data.Users.default_user_id()) do
    AIBrain.Interaction.Manager.resolve(interaction_id, result, resolved_by)
  end

  @doc "Get the interaction chain for a session — rendered for the frontend."
  def session_chain(session_id) do
    AIBrain.Interaction.Manager.session_chain(session_id)
  end

  @doc "Get a single interaction by ID."
  def get(interaction_id) do
    AIBrain.Data.Interactions.get(interaction_id)
  end
end
