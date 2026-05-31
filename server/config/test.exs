import Config

config :ai_brain, AIBrain.Repo,
  database: Path.join(System.tmp_dir!(), "aibrain_test_data/brain_test.db"),
  pool: Ecto.Adapters.SQL.Sandbox

config :ai_brain, :session_store, AIBrain.Session.Store.Memory
config :ai_brain, :data_dir, Path.join(System.tmp_dir!(), "aibrain_test_data")
config :ai_brain, :config_dir, Path.join(System.tmp_dir!(), "aibrain_test_data/.aibrain")

config :ai_brain, :disable_http, true
config :ai_brain, :port, 4002
config :ai_brain, :task_dispatcher_enabled, false
config :ai_brain, :proxy_enabled, false
config :ai_brain, :background_services_enabled, false
config :ai_brain, :startup_jobs_enabled, false
config :ai_brain, :engine_recovery_enabled, false
config :ai_brain, :telemetry_persist_enabled, false
config :ai_brain, :memory_parallelism, false

config :ai_brain, :llm_context, AIBrain.LLM.ContextMock
