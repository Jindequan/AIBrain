defmodule AIBrain.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring access to the application's
  data layer via Ecto. Each test runs inside an Ecto sandbox transaction that
  is rolled back after the test, keeping the database clean.

  Usage:

      defmodule MyApp.SomeSchemaTest do
        use AIBrain.DataCase
        ...
      end

  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      alias AIBrain.Repo

      import AIBrain.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AIBrain.Repo, shared: not tags[:async])

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    :ok
  end
end
