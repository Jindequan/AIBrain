defmodule AIBrain.MigrationRunner do
  @moduledoc """
  Runs database migrations during application startup.

  This child is placed immediately after Repo in the supervision tree. Returning
  `:ignore` lets supervision continue after migrations complete, while ensuring
  later services never boot against an old schema.
  """

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(_opts) do
    Logger.info("Running database migrations...")

    Ecto.Migrator.run(AIBrain.Repo, :up, all: true)

    Logger.info("Database migrations completed")
    :ignore
  rescue
    e ->
      Logger.error("FATAL: Database migration failed: #{Exception.message(e)}")
      {:error, "migration_failed"}
  end
end
