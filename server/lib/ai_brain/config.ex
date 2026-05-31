defmodule AIBrain.Config do
  @moduledoc """
  Centralized runtime configuration accessors.

  Prevents scattered `Application.get_env` calls with inconsistent defaults
  across the codebase. All config resolution should go through this module.
  """

  @doc """
  Returns the configured session store module.
  Defaults to `AIBrain.Session.Store.Memory`.
  """
  @spec session_store() :: module()
  def session_store do
    Application.get_env(:ai_brain, :session_store, AIBrain.Session.Store.Memory)
  end

  @doc """
  Returns the configured data directory.
  Defaults to `~/.aibrain`.
  """
  @spec data_dir() :: String.t()
  def data_dir do
    Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))
  end

  @doc """
  Returns the configured HTTP port.
  Reads from AIBRAIN_PORT, PORT, or application config (default 4000).
  """
  @spec port() :: pos_integer()
  def port do
    case System.get_env("AIBRAIN_PORT") || System.get_env("PORT") do
      nil -> Application.get_env(:ai_brain, :port, 4000)
      env_port -> String.to_integer(env_port)
    end
  end

  @doc """
  Returns the configured workspace path.
  Defaults to the user's home directory.
  """
  @spec workspace_path() :: String.t() | nil
  def workspace_path do
    Application.get_env(:ai_brain, :workspace_path)
  end

  @doc """
  Returns CORS allowed origins.
  """
  @spec cors_origins() :: [String.t()]
  def cors_origins do
    Application.get_env(:ai_brain, :cors_origins, [
      "http://localhost:3000",
      "http://localhost:5173",
      "http://127.0.0.1:3000",
      "http://127.0.0.1:5173"
    ])
  end
end
