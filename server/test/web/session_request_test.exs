defmodule AIBrain.Web.SessionRequestTest do
  use ExUnit.Case, async: true

  alias AIBrain.Web.Handlers.Session.Request

  test "runtime opts use the unified interactive run mode" do
    request = Request.build_for_resume("session-1", %{"message" => "hello", "mode" => "default"})
    opts = Request.to_runtime_opts(request, AIBrain.Session.Store.Memory)

    assert opts[:session_id] == "session-1"
    assert opts[:mode] == "interactive"
    assert opts[:style] == :default
    assert opts[:permission_mode] == :approval_required
  end

  test "create requests may be empty so chat can create a session before first send" do
    request = Request.build_from_params(%{})

    assert Request.validate(request, :create) == :ok
    assert request.messages == []
  end

  test "unknown channel adapter values do not crash request parsing" do
    request = Request.build_from_params(%{"channel_adapter" => "unknown_adapter"})

    assert request.channel_adapter == nil
  end
end
