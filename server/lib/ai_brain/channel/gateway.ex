defmodule AIBrain.Channel.Gateway do
  @moduledoc """
  Supervisor for channel adapter workers.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    # Read adapters from opts or fall back to application environment
    # This allows dynamic reloading via application env
    adapters =
      Keyword.get(opts, :adapters) ||
        Application.get_env(:ai_brain, :gateway_adapters, [])

    # Start a Registry for worker names FIRST
    registry_child = {Registry, [keys: :unique, name: AIBrain.Channel.Gateway.Registry]}

    # Then adapter workers
    adapter_children =
      adapters
      |> Enum.with_index()
      |> Enum.map(fn {{adapter_mod, adapter_opts}, idx} ->
        worker_key = {adapter_mod, idx}
        worker_id = {__MODULE__, adapter_mod, idx}

        %{
          id: worker_id,
          start: {
            AIBrain.Channel.AdapterWorker,
            :start_link,
            [
              [
                adapter: adapter_mod,
                adapter_opts: adapter_opts,
                channel: adapter_mod.channel(),
                registry: {AIBrain.Channel.Gateway.Registry, worker_key}
              ]
            ]
          }
        }
      end)

    # Registry must come first
    children = [registry_child | adapter_children]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def adapter_worker(name, idx \\ 0) do
    {AIBrain.Channel.Gateway.Registry, {name, idx}}
  end
end
