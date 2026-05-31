data_dir =
  Application.get_env(:ai_brain, :data_dir, Path.join(System.tmp_dir!(), "aibrain_test_data"))

File.rm_rf!(Path.join(data_dir, "sessions"))
File.mkdir_p!(data_dir)

ExUnit.start()

# Configure Ecto sandbox for tests that use Repo directly
Ecto.Adapters.SQL.Sandbox.mode(AIBrain.Repo, :manual)
