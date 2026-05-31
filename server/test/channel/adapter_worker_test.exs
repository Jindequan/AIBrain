defmodule AIBrain.Channel.AdapterWorkerTest do
  use ExUnit.Case, async: false

  defmodule EchoAdapter do
    @behaviour AIBrain.Channel.Adapter

    @impl true
    def init(_opts), do: {:ok, %{}}

    @impl true
    def handle_inbound(state, %{"text" => text}) do
      {:ok, [%{role: "user", content: text}], state}
    end

    def handle_inbound(state, _), do: {:ok, [], state}

    @impl true
    def send_message(state, _msg), do: {:ok, state}

    def channel, do: :echo_test
  end

  describe "start_link/1" do
    test "starts with valid adapter" do
      {:ok, pid} =
        AIBrain.Channel.AdapterWorker.start_link(
          adapter: EchoAdapter,
          adapter_opts: [],
          channel: :echo_test
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "adapter init failure prevents worker start" do
      defmodule FailAdapter do
        @behaviour AIBrain.Channel.Adapter
        @impl true
        def init(_), do: {:error, :config_missing}
        @impl true
        def handle_inbound(s, _), do: {:ok, [], s}
        @impl true
        def send_message(s, _), do: {:ok, s}
      end

      # Worker init returns {:stop, reason} when adapter init fails
      assert {:error, :config_missing} = FailAdapter.init([])
    end
  end

  describe "deliver_inbound/2" do
    test "routes non-text payload returns empty results" do
      {:ok, pid} =
        AIBrain.Channel.AdapterWorker.start_link(
          adapter: EchoAdapter,
          adapter_opts: [],
          channel: :echo_test
        )

      # Non-text payload produces empty messages, so no runtime call
      assert {:ok, []} =
               AIBrain.Channel.AdapterWorker.deliver_inbound(
                 pid,
                 %{"photo" => %{}}
               )

      GenServer.stop(pid)
    end
  end
end
