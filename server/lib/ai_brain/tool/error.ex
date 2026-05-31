defmodule AIBrain.Tool.Error do
  @moduledoc """
  Structured tool failure with category classification.
  """

  @type category ::
          :permission | :invalid_params | :execution | :external_service | :timeout | :unavailable

  @type t :: %__MODULE__{
          category: category(),
          message: String.t(),
          details: map()
        }

  defstruct [:category, :message, details: %{}]

  def permission(msg), do: %__MODULE__{category: :permission, message: msg}
  def invalid_params(msg), do: %__MODULE__{category: :invalid_params, message: msg}
  def execution(msg), do: %__MODULE__{category: :execution, message: msg}
  def external_service(msg), do: %__MODULE__{category: :external_service, message: msg}

  def timeout(msg, opts \\ []) do
    %__MODULE__{
      category: :timeout,
      message: msg,
      details: opts |> Keyword.take([:tool_timeout, :command]) |> Map.new()
    }
  end

  def unavailable(msg), do: %__MODULE__{category: :unavailable, message: msg}

  @doc """
  Convert any error value to a Tool.Error.
  Passes through existing Tool.Error structs.
  Wraps strings, crash tuples, and unknown terms as :execution.
  """
  @spec from(term()) :: t()
  def from(%__MODULE__{} = e), do: e
  def from(msg) when is_binary(msg), do: %__MODULE__{category: :execution, message: msg}

  def from({:tool_crash, reason}),
    do: %__MODULE__{category: :execution, message: "Tool crashed: #{inspect(reason)}"}

  def from({:tool_exit, reason}),
    do: %__MODULE__{category: :execution, message: "Tool exited: #{inspect(reason)}"}

  def from({:tool_throw, reason}),
    do: %__MODULE__{category: :execution, message: "Tool threw: #{inspect(reason)}"}

  def from(other), do: %__MODULE__{category: :execution, message: inspect(other)}
end
