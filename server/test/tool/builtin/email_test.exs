defmodule AIBrain.Tool.Builtin.EmailTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Email

  describe "callbacks" do
    test "name is email" do
      assert Email.name() == "email"
    end

    test "description is set" do
      assert is_binary(Email.description())
    end

    test "input_schema is valid" do
      schema = Email.input_schema()
      assert schema["type"] == "object"
      assert schema["required"] == ["action"]

      assert schema["properties"]["action"]["enum"] == [
               "send",
               "read_inbox",
               "search",
               "reply",
               "mark_read",
               "archive"
             ]
    end

    test "not read_only" do
      refute Email.read_only?()
    end

    test "risk_category is :network" do
      assert Email.risk_category() == :network
    end
  end

  describe "execute/2 — validation" do
    test "errors on missing action" do
      assert {:error, msg} = Email.execute(%{}, %{})
      assert msg =~ "send"
    end

    test "send errors on missing to" do
      assert {:error, _} = Email.execute(%{"action" => "send"}, %{})
    end

    test "send errors on missing subject" do
      assert {:error, _} = Email.execute(%{"action" => "send", "to" => "a@b.com"}, %{})
    end

    test "send errors on missing body" do
      assert {:error, _} =
               Email.execute(%{"action" => "send", "to" => "a@b.com", "subject" => "hi"}, %{})
    end

    test "send errors when no backend configured" do
      assert {:error, msg} =
               Email.execute(
                 %{"action" => "send", "to" => "a@b.com", "subject" => "hi", "body" => "hello"},
                 %{}
               )

      assert msg =~ "backend" or msg =~ "not configured"
    end

    test "read_inbox errors when no backend configured" do
      assert {:error, msg} = Email.execute(%{"action" => "read_inbox"}, %{})
      assert msg =~ "backend" or msg =~ "not configured"
    end

    test "search requires query" do
      assert {:error, msg} = Email.execute(%{"action" => "search"}, %{})
      assert msg =~ "query"
    end

    test "reply requires message_id" do
      assert {:error, msg} = Email.execute(%{"action" => "reply"}, %{})
      assert msg =~ "message_id"
    end

    test "smtp reply requires recipient metadata instead of returning an unimplemented error" do
      old_config = Application.get_env(:ai_brain, :email)

      Application.put_env(:ai_brain, :email, %{
        smtp_server: "smtp.example.com",
        username: "me@example.com",
        password: "secret"
      })

      on_exit(fn ->
        if old_config do
          Application.put_env(:ai_brain, :email, old_config)
        else
          Application.delete_env(:ai_brain, :email)
        end
      end)

      assert {:error, msg} =
               Email.execute(%{"action" => "reply", "message_id" => "m1", "body" => "ok"}, %{})

      assert msg =~ "requires recipient"
      refute msg =~ "not implemented"
    end

    test "mark_read requires message_id" do
      assert {:error, msg} = Email.execute(%{"action" => "mark_read"}, %{})
      assert msg =~ "message_id"
    end

    test "archive requires message_id" do
      assert {:error, msg} = Email.execute(%{"action" => "archive"}, %{})
      assert msg =~ "message_id"
    end
  end
end
