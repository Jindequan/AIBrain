defmodule AIBrain.Web.RunsHandlerTest do
  use AIBrain.DataCase
  import Plug.Test

  alias AIBrain.AgentRuntime.{Evidence, FileStore}
  alias AIBrain.Data.{RunContextRefs, Runs, RunSteps}
  alias AIBrain.Web.Handlers.RunsHandler

  setup do
    data_dir =
      System.tmp_dir!() |> Path.join("runs_handler_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(data_dir)
    Application.put_env(:ai_brain, :data_dir, data_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      Application.delete_env(:ai_brain, :data_dir)
    end)

    :ok
  end

  test "GET run includes normalized context and steps" do
    {:ok, run} =
      Runs.create_run(%{
        source_type: "task",
        source_id: "task-1",
        status: "running",
        phase: "executing",
        objective: "finish task"
      })

    {:ok, _step} =
      RunSteps.create(%{
        run_id: run.id,
        step_index: 0,
        phase: "executing",
        status: "running",
        kind: "llm",
        title: "Agent transaction"
      })

    conn = conn(:get, "/api/v1/runs/#{run.id}")
    conn = RunsHandler.handle_get(conn, run.id)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["run"]["id"] == run.id
    assert body["context"]["run_id"] == run.id
    assert [%{"kind" => "llm"}] = body["context"]["steps"]
  end

  test "list supports source and normalized context filters" do
    {:ok, goal_run} =
      Runs.create_run(%{
        source_type: "schedule",
        source_id: "schedule-1",
        status: "completed",
        phase: "reporting",
        mode: "background"
      })

    {:ok, task_run} =
      Runs.create_run(%{
        source_type: "task",
        source_id: "task-1",
        status: "completed",
        phase: "reporting",
        mode: "background"
      })

    :ok =
      RunContextRefs.create_many(goal_run.id, [
        %{ref_type: "goal", ref_id: "goal-1", role: "primary"},
        %{ref_type: "schedule", ref_id: "schedule-1", role: "trigger"}
      ])

    :ok =
      RunContextRefs.create_many(task_run.id, [
        %{ref_type: "task", ref_id: "task-1", role: "primary"}
      ])

    source_conn =
      RunsHandler.handle_list(conn(:get, "/api/v1/runs"), %{
        "source_type" => "schedule",
        "source_id" => "schedule-1"
      })

    ref_conn =
      RunsHandler.handle_list(conn(:get, "/api/v1/runs"), %{
        "ref_type" => "goal",
        "ref_id" => "goal-1"
      })

    assert [%{"id" => source_id, "run_id" => source_run_id}] =
             Jason.decode!(source_conn.resp_body)["runs"]

    assert source_id == goal_run.id
    assert source_run_id == goal_run.id

    assert [%{"id" => ref_id, "run_id" => ref_run_id}] = Jason.decode!(ref_conn.resp_body)["runs"]
    assert ref_id == goal_run.id
    assert ref_run_id == goal_run.id
  end

  test "output, events, and messages are read from run files" do
    {:ok, run} = Runs.create_run(%{source_type: "manual", status: "completed"})
    {:ok, output_path} = FileStore.write_output(run.id, "final text")

    {:ok, _run} =
      Runs.update_run(run.id, %{output_path: output_path, output_summary: "final text"})

    :ok = FileStore.append_event(run.id, %{type: :tool_result, result: {:ok, "tuple-safe"}})
    :ok = FileStore.append_message(run.id, %{"role" => "assistant", "content" => "hello"})

    output_conn = RunsHandler.handle_output(conn(:get, "/api/v1/runs/#{run.id}/output"), run.id)

    events_conn =
      RunsHandler.handle_events(conn(:get, "/api/v1/runs/#{run.id}/events"), run.id, %{})

    messages_conn =
      RunsHandler.handle_messages(conn(:get, "/api/v1/runs/#{run.id}/messages"), run.id)

    assert Jason.decode!(output_conn.resp_body)["output"] == "final text"

    assert [%{"result" => "{:ok, \"tuple-safe\"}"}] =
             Jason.decode!(events_conn.resp_body)["events"]

    assert [%{"role" => "assistant", "content" => "hello"} | _] =
             Jason.decode!(messages_conn.resp_body)["messages"]
  end

  test "cancel updates run and open steps through lifecycle" do
    {:ok, run} = Runs.create_run(%{source_type: "manual", status: "running", phase: "executing"})

    {:ok, step} =
      RunSteps.create(%{
        run_id: run.id,
        step_index: 0,
        phase: "executing",
        status: "running",
        kind: "llm",
        title: "Agent transaction"
      })

    conn = RunsHandler.handle_cancel(conn(:post, "/api/v1/runs/#{run.id}/cancel"), run.id)

    assert conn.status == 200
    assert {:ok, updated} = Runs.get_run(run.id)
    assert updated.status == "cancelled"
    assert updated.phase == "cancelled"

    steps = RunSteps.list_for_run(run.id)
    assert Enum.any?(steps, &(&1.id == step.id and &1.status == "cancelled"))
    assert Enum.any?(steps, &(&1.phase == "cancelled" and &1.title == "Run cancelled"))
  end

  describe "steps/2" do
    test "returns steps for a run" do
      {:ok, run} = Runs.create_run(%{source_type: "manual", status: "running"})

      {:ok, _} =
        RunSteps.create(%{
          run_id: run.id,
          step_index: 0,
          phase: "analysis",
          status: "completed",
          kind: "system",
          title: "Policy selected"
        })

      {:ok, _} =
        RunSteps.create(%{
          run_id: run.id,
          step_index: 1,
          phase: "executing",
          status: "running",
          kind: "llm",
          title: "Agent transaction"
        })

      conn = RunsHandler.handle_steps(conn(:get, "/api/v1/runs/#{run.id}/steps"), run.id, %{})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["run_id"] == run.id
      assert length(body["steps"]) == 2
      assert hd(body["steps"])["title"] == "Policy selected"
    end

    test "filters steps by phase" do
      {:ok, run} = Runs.create_run(%{source_type: "manual", status: "running"})

      {:ok, _} =
        RunSteps.create(%{
          run_id: run.id,
          step_index: 0,
          phase: "analysis",
          status: "completed",
          kind: "system",
          title: "Analysis step"
        })

      {:ok, _} =
        RunSteps.create(%{
          run_id: run.id,
          step_index: 1,
          phase: "executing",
          status: "running",
          kind: "llm",
          title: "Executing step"
        })

      conn =
        RunsHandler.handle_steps(conn(:get, "/api/v1/runs/#{run.id}/steps"), run.id, %{
          "phase" => "executing"
        })

      body = Jason.decode!(conn.resp_body)
      assert length(body["steps"]) == 1
      assert hd(body["steps"])["title"] == "Executing step"
    end

    test "returns 404 for unknown run" do
      conn =
        RunsHandler.handle_steps(conn(:get, "/api/v1/runs/nonexistent/steps"), "nonexistent", %{})

      assert conn.status == 404
    end
  end

  describe "evidence/2" do
    test "returns evidence for a run" do
      {:ok, run} = Runs.create_run(%{source_type: "manual", status: "completed"})

      {:ok, _} =
        Evidence.record(%{
          run_id: run.id,
          claim: "Test evidence claim",
          source_type: "file_read",
          tool_name: "file_read",
          confidence: 0.9
        })

      conn = RunsHandler.handle_evidence(conn(:get, "/api/v1/runs/#{run.id}/evidence"), run.id)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["run_id"] == run.id
      assert length(body["evidence"]) == 1
      assert hd(body["evidence"])["claim"] == "Test evidence claim"
      assert hd(body["evidence"])["confidence"] == 0.9
    end

    test "returns empty list when no evidence" do
      {:ok, run} = Runs.create_run(%{source_type: "manual", status: "completed"})

      conn = RunsHandler.handle_evidence(conn(:get, "/api/v1/runs/#{run.id}/evidence"), run.id)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["evidence"] == []
    end
  end

  describe "verification/2" do
    test "returns verification from run metadata" do
      {:ok, run} =
        Runs.create_run(%{
          source_type: "task",
          status: "completed",
          metadata: %{
            "verification" => %{
              "status" => "warning",
              "warnings" => ["No tools were executed."],
              "failures" => [],
              "unknowns" => []
            }
          }
        })

      conn =
        RunsHandler.handle_verification(conn(:get, "/api/v1/runs/#{run.id}/verification"), run.id)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["verification"]["status"] == "warning"
      assert body["verification"]["warnings"] == ["No tools were executed."]
    end

    test "returns nil verification when not yet verified" do
      {:ok, run} = Runs.create_run(%{source_type: "manual", status: "running"})

      conn =
        RunsHandler.handle_verification(conn(:get, "/api/v1/runs/#{run.id}/verification"), run.id)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["verification"] == nil
      assert body["note"] =~ "not been verified"
    end
  end

  describe "stats/2" do
    test "returns aggregate run statistics" do
      Runs.create_run(%{source_type: "manual", status: "completed", mode: "direct"})
      Runs.create_run(%{source_type: "manual", status: "running", mode: "work"})
      Runs.create_run(%{source_type: "task", status: "failed", mode: "project"})

      conn = RunsHandler.handle_stats(conn(:get, "/api/v1/runs/stats"), %{})

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["total_runs"] >= 3
      assert is_map(body["by_status"])
      assert is_map(body["by_mode"])
      assert is_list(body["recent_runs"])
    end
  end
end
