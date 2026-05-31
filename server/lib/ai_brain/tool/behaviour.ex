defmodule AIBrain.Tool.Behaviour do
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()

  @callback execute(args :: map(), context :: map()) ::
              {:ok, String.t() | map()}
              | {:error, String.t() | map()}

  @callback read_only?() :: boolean()
  @callback risk_category() :: :read_only | :workspace_write | :shell_exec | :network | :unknown

  # Timeout in milliseconds - nil means no timeout (let tool run indefinitely)
  @callback timeout() :: integer() | nil

  # nil = always visible; "skill_name" = only visible after that skill is loaded
  @callback skill_owner() :: String.t() | nil

  @callback available?() :: boolean()
  @callback summarize(output :: String.t(), opts :: keyword()) :: String.t()

  @optional_callbacks risk_category: 0, timeout: 0, skill_owner: 0, available?: 0, summarize: 2
end
