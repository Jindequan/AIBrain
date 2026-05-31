defmodule AIBrain.Core.ErrorFormatterTest do
  use ExUnit.Case, async: true

  alias AIBrain.Core.ErrorFormatter

  test "exception and provider details are mapped to public messages" do
    assert ErrorFormatter.format_en(
             {:exception, "DBConnection.ConnectionError: pool exhausted", RuntimeError}
           ) ==
             "Internal error: DBConnection.ConnectionError: pool exhausted"

    assert ErrorFormatter.format_en({:provider_error, "API key 无效或已过期，请检查 Zhipu 的 API key 配置"}) ==
             "API key 无效或已过期，请检查 Zhipu 的 API key 配置"

    assert ErrorFormatter.format_en(:rate_limited) ==
             "AI service is busy. Please try again later."
  end
end
