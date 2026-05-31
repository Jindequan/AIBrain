defmodule AIBrain.Tool.WebFetchSSRFTest do
  use ExUnit.Case, async: true

  alias AIBrain.Tool.Builtin.WebFetch

  test "blocks localhost URLs" do
    assert {:error, msg} =
             WebFetch.execute(%{"url" => "http://localhost:4000/api/v1/providers"}, %{})

    assert String.contains?(msg, "blocked")
  end

  test "blocks 127.0.0.1" do
    assert {:error, msg} = WebFetch.execute(%{"url" => "http://127.0.0.1:8080/secret"}, %{})
    assert String.contains?(msg, "blocked")
  end

  test "blocks private 192.168.x.x" do
    assert {:error, msg} = WebFetch.execute(%{"url" => "http://192.168.1.1/"}, %{})
    assert String.contains?(msg, "blocked")
  end

  test "blocks private 10.x.x.x" do
    assert {:error, msg} = WebFetch.execute(%{"url" => "http://10.0.0.1/"}, %{})
    assert String.contains?(msg, "blocked")
  end

  test "allows normal public URLs" do
    # Doesn't actually make a request — only tests URL validation logic
    assert :ok == AIBrain.Business.WebContent.UrlValidator.validate("https://example.com")
  end
end
