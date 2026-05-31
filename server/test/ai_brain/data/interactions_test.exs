defmodule AIBrain.Data.InteractionsTest do
  use AIBrain.DataCase, async: false

  alias AIBrain.Data.Interactions
  alias AIBrain.Interaction.Manager

  describe "expire/1" do
    test "marks pending interaction as expired" do
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)
      assert {:ok, i} = Interactions.expire(id)
      assert i.status == "expired"
    end

    test "marks proxy_running interaction as expired" do
      {:ok, id} = Manager.request(:confirm, %{"title" => "Test"}, %{}, expires_in: 300)
      Interactions.claim_for_proxy(id)
      assert {:ok, i} = Interactions.expire(id)
      assert i.status == "expired"
    end

    test "returns error for already resolved interaction" do
      {:ok, id} = Manager.request(:confirm, %{"title" => "Test"}, %{}, expires_in: 300)
      Interactions.resolve(id, %{}, AIBrain.Data.Users.default_user_id())
      assert {:error, :wrong_status} = Interactions.expire(id)
    end

    test "returns error for non-existent interaction" do
      assert {:error, :not_found} = Interactions.expire("nonexistent-id")
    end
  end

  describe "record_proxy_decision/3" do
    test "appends trail entry atomically" do
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)

      entry = %{step: "assessment", action: "evaluate", reasoning: "Auto-approvable"}
      assert {:ok, i} = Interactions.record_proxy_decision(id, entry)
      assert length(i.proxy_trail) == 1
      assert hd(i.proxy_trail)["step"] == "assessment"
      assert hd(i.proxy_trail)["action"] == "evaluate"
      assert hd(i.proxy_trail)["recorded_at"]
    end

    test "appends multiple entries in order" do
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)

      Interactions.record_proxy_decision(id, %{step: "1-evaluate"})
      Interactions.record_proxy_decision(id, %{step: "2-decide"})
      assert {:ok, i} = Interactions.record_proxy_decision(id, %{step: "3-resolve"})

      assert length(i.proxy_trail) == 3
      assert Enum.map(i.proxy_trail, & &1["step"]) == ["1-evaluate", "2-decide", "3-resolve"]
    end

    test "can update status alongside trail entry" do
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)

      assert {:ok, i} =
               Interactions.record_proxy_decision(id, %{step: "finalize", action: "submit"},
                 status: "resolved"
               )

      assert length(i.proxy_trail) == 1
      assert i.status == "resolved"
    end

    test "returns error for non-existent interaction" do
      assert {:error, :not_found} =
               Interactions.record_proxy_decision("bad-id", %{step: "test"})
    end
  end

  describe "expired/0" do
    test "returns interactions past their expires_at" do
      # Create an interaction with a past expiry
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)

      # Force the expires_at into the past
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()
      interaction = Interactions.get(id)
      Ecto.Changeset.change(interaction, expires_at: past) |> AIBrain.Repo.update!()

      expired_list = Interactions.expired()
      assert Enum.any?(expired_list, &(&1.id == id))
    end

    test "does not return already resolved interactions" do
      {:ok, id} = Manager.request(:approval, %{"title" => "Test"}, %{}, expires_in: 300)
      past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()
      interaction = Interactions.get(id)

      Ecto.Changeset.change(interaction, status: "resolved", expires_at: past)
      |> AIBrain.Repo.update!()

      expired_list = Interactions.expired()
      refute Enum.any?(expired_list, &(&1.id == id))
    end
  end

  describe "count_by_status/1" do
    test "returns count of interactions with given status" do
      count = Interactions.count_by_status("pending")
      assert is_integer(count)
    end
  end
end
