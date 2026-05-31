defmodule AIBrain.LLM.ClientTest do
  use ExUnit.Case, async: false
  import Mox

  alias AIBrain.LLM.Client
  alias AIBrain.LLM.Adapters.Protocol.OpenAI
  alias AIBrain.Provider.Info

  setup :verify_on_exit!

  defp make_provider do
    %Info{
      name: "Test",
      api_key: "test-key",
      base_url: "http://fake-llm",
      chat_url: "http://fake-llm/v1/chat",
      priority: 1
    }
  end

  # ---------------------------------------------------------------------------
  # build_body (OpenAI protocol adapter)
  # ---------------------------------------------------------------------------

  test "build_body for openai protocol" do
    messages = [%{role: "user", content: "hello"}]

    tools = [
      %{name: "bash", description: "run bash", input_schema: %{type: "object", properties: %{}}}
    ]

    body =
      OpenAI.build_body(make_provider(), messages, tools,
        system: "be helpful",
        model: "gpt-test"
      )

    assert body["model"] == "gpt-test"
    assert body["stream"] == true
    assert [%{role: "system", content: "be helpful"} | _] = body["messages"]
  end

  # ---------------------------------------------------------------------------
  # stream/4 error handling
  # ---------------------------------------------------------------------------

  test "stream/4 returns {:error, :transport, exception} when Req.post raises a transport error" do
    exception = %Mint.TransportError{reason: :econnrefused}

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, _opts -> {:error, exception} end)

    result = Client.stream(make_provider(), [], [], http_client: AIBrain.LLM.HTTPMock)
    assert {:error, :transport, ^exception} = result
  end

  test "stream/4 returns {:error, :http, status, headers, body} when server responds with 429" do
    headers = [{"retry-after", "30"}]
    body = %{"error" => %{"type" => "rate_limit_error", "message" => "Rate limited"}}
    response = %Req.Response{status: 429, headers: headers, body: body}

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, _opts -> {:ok, response} end)

    result = Client.stream(make_provider(), [], [], http_client: AIBrain.LLM.HTTPMock)
    assert {:error, :http, 429, ^headers, ^body} = result
  end

  test "stream/4 sends streamed events and completion signal on successful response" do
    response = %Req.Response{status: 200, headers: [], body: ""}

    AIBrain.LLM.HTTPMock
    |> expect(:post, fn _url, opts ->
      assert {:cont, _state} =
               opts[:into].(
                 {:data, "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"},\"index\":0}]}\n"},
                 {:req, :resp}
               )

      {:ok, response}
    end)

    result = Client.stream(make_provider(), [], [], http_client: AIBrain.LLM.HTTPMock)
    assert {:ok, :streaming_complete} = result
    assert_received {:sse_event, {:text_delta, "Hi"}}
    assert_received {:sse_done}
  end
end
