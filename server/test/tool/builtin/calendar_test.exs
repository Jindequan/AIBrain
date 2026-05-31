defmodule AIBrain.Tool.Builtin.CalendarTest do
  use ExUnit.Case, async: true
  alias AIBrain.Tool.Builtin.Calendar

  describe "callbacks" do
    test "name is calendar" do
      assert Calendar.name() == "calendar"
    end

    test "description is set" do
      assert is_binary(Calendar.description())
    end

    test "input_schema is valid" do
      schema = Calendar.input_schema()
      assert schema["type"] == "object"
      assert schema["required"] == ["action"]

      assert schema["properties"]["action"]["enum"] == [
               "list_events",
               "create_event",
               "delete_event",
               "find_free_slot"
             ]
    end

    test "not read_only" do
      refute Calendar.read_only?()
    end

    test "risk_category is :network" do
      assert Calendar.risk_category() == :network
    end
  end

  describe "execute/2 — validation" do
    test "errors on unknown action" do
      assert {:error, _} = Calendar.execute(%{"action" => "invalid"}, %{})
    end

    test "list_events when no calendar configured" do
      assert {:error, msg} = Calendar.execute(%{"action" => "list_events"}, %{})
      assert msg =~ "backend" or msg =~ "not configured" or msg =~ "calendar"
    end

    test "create_event errors when start missing" do
      assert {:error, msg} =
               Calendar.execute(
                 %{"action" => "create_event", "end" => "2025-01-15T15:00:00"},
                 %{}
               )

      assert msg =~ "start"
    end

    test "create_event errors when end missing" do
      assert {:error, msg} =
               Calendar.execute(
                 %{"action" => "create_event", "start" => "2025-01-15T14:00:00"},
                 %{}
               )

      assert msg =~ "end"
    end

    test "create_event when no calendar backend configured" do
      assert {:error, msg} =
               Calendar.execute(
                 %{
                   "action" => "create_event",
                   "start" => "2025-01-15T14:00:00",
                   "end" => "2025-01-15T15:00:00",
                   "summary" => "Test"
                 },
                 %{}
               )

      assert msg =~ "backend" or msg =~ "configured" or msg =~ "calendar"
    end

    test "delete_event requires event_id" do
      assert {:error, msg} = Calendar.execute(%{"action" => "delete_event"}, %{})
      assert msg =~ "event_id"
    end

    test "find_free_slot returns error when no backend configured" do
      result = Calendar.execute(%{"action" => "find_free_slot"}, %{})
      assert {:error, _} = result
    end
  end
end
