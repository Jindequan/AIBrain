defmodule AIBrain.Interaction.ManagerTest do
  use AIBrain.DataCase, async: false

  alias AIBrain.Data.{Goals, Interactions}
  alias AIBrain.Interaction.Manager

  test "creates approval interactions for suspended runs" do
    schema = %{
      "title" => "Approval required",
      "prompt" => "Approve this action?",
      "fields" => [%{"name" => "decision", "type" => "select"}]
    }

    context = %{
      "run_id" => "run-1",
      "step_id" => "step-1",
      "tool" => "file_write"
    }

    assert {:ok, interaction_id} =
             Manager.request(:approval, schema, context, resume_token: "resume-token-1")

    interaction = Interactions.get(interaction_id)

    assert interaction.type == "approval"
    assert interaction.status == "pending"
    assert interaction.schema_data == schema
    assert interaction.context == context
    assert interaction.resume_token == "resume-token-1"
  end

  test "resolving goal owner input unblocks the goal for review" do
    {:ok, goal} =
      Goals.create(%{
        title: "Creator account",
        metadata: %{
          "next_review_after" => "2099-01-01T00:00:00Z",
          "strategy" => %{
            "needs_owner_input" => true,
            "next_actions" => ["Review analytics"]
          }
        }
      })

    {:ok, interaction_id} =
      Manager.request(
        :form,
        %{"title" => "Need input"},
        %{"kind" => "goal_owner_input", "goal_id" => goal.id},
        expires_in: 300
      )

    assert :ok =
             Manager.resolve(
               interaction_id,
               %{"decision" => "continue", "response" => "Analytics is connected."},
               "user"
             )

    {:ok, updated} = Goals.get(goal.id)
    assert updated.status == "active"
    assert updated.metadata["strategy"]["needs_owner_input"] == false
    assert updated.metadata["strategy"]["owner_decision"] == "continue"
    assert updated.metadata["strategy"]["owner_response"] == "Analytics is connected."
    assert updated.metadata["last_owner_interaction_decision"] == "continue"
    assert updated.metadata["next_review_after"] != "2099-01-01T00:00:00Z"
  end

  test "resolving goal owner input can pause the goal" do
    {:ok, goal} =
      Goals.create(%{
        title: "Health management",
        metadata: %{"next_review_after" => "2099-01-01T00:00:00Z"}
      })

    {:ok, interaction_id} =
      Manager.request(
        :form,
        %{"title" => "Need input"},
        %{"kind" => "goal_owner_input", "goal_id" => goal.id},
        expires_in: 300
      )

    assert :ok =
             Manager.resolve(
               interaction_id,
               %{"decision" => "pause_goal", "response" => "Pause until next month."},
               "user"
             )

    {:ok, updated} = Goals.get(goal.id)
    assert updated.status == "paused"
    assert updated.metadata["last_owner_interaction_decision"] == "pause_goal"
    refute Map.has_key?(updated.metadata, "next_review_after")
  end

  test "resolving goal owner input can keep strategy in revision mode" do
    {:ok, goal} =
      Goals.create(%{
        title: "Research project",
        metadata: %{"strategy" => %{"needs_owner_input" => true}}
      })

    {:ok, interaction_id} =
      Manager.request(
        :form,
        %{"title" => "Need input"},
        %{"kind" => "goal_owner_input", "goal_id" => goal.id},
        expires_in: 300
      )

    assert :ok =
             Manager.resolve(
               interaction_id,
               %{"decision" => "revise_strategy", "response" => "Change the target audience."},
               "user"
             )

    {:ok, updated} = Goals.get(goal.id)
    assert updated.status == "active"
    assert updated.metadata["strategy"]["needs_owner_input"] == true
    assert updated.metadata["strategy"]["owner_decision"] == "revise_strategy"
    assert updated.metadata["next_review_after"]
  end

  test "proxy resolution applies goal owner input and persists proxy trail" do
    {:ok, goal} =
      Goals.create(%{
        title: "Autonomous creator ops",
        metadata: %{"strategy" => %{"needs_owner_input" => true}}
      })

    {:ok, interaction_id} =
      Manager.request(
        :form,
        %{"title" => "Need input"},
        %{"kind" => "goal_owner_input", "goal_id" => goal.id},
        expires_in: 300
      )

    proxy_trail = [%{step: "assessment", action: "submit", reasoning: "Known preference"}]

    assert :ok =
             Manager.resolve(
               interaction_id,
               %{form: %{decision: "continue", response: "Use my standing preference."}},
               "proxy",
               proxy_trail: proxy_trail
             )

    interaction = Interactions.get(interaction_id)
    assert interaction.resolved_by == "proxy"

    assert interaction.proxy_trail == [
             %{"action" => "submit", "reasoning" => "Known preference", "step" => "assessment"}
           ]

    {:ok, updated} = Goals.get(goal.id)
    assert updated.status == "active"
    assert updated.metadata["strategy"]["needs_owner_input"] == false
    assert updated.metadata["strategy"]["owner_decision"] == "continue"
    assert updated.metadata["strategy"]["owner_response"] == "Use my standing preference."
    assert updated.metadata["last_owner_interaction_resolved_by"] == "proxy"
  end
end
