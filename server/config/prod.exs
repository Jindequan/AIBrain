import Config

# Production log level keeps lifecycle/retry/degradation events visible.
config :logger, level: :info

# Static files directory for serving the frontend SPA build.
# In production, the bin/build script copies frontend/dist into
# the release's priv/static directory (accessible via from: :ai_brain in Plug.Static).
# Override at runtime by setting the STATIC_DIR environment variable
# in the application start (see AIBrain.Application.start/2).
config :ai_brain, :static_dir, Path.expand("../../web/dist", __DIR__)

# Environment hint for runtime (avoids Mix.env() in function bodies)
config :ai_brain, :env, :prod

# Production database config (same default as dev)
config :ai_brain, AIBrain.Repo,
  database: Path.expand("~/.aibrain/brain.db"),
  pool_size: System.get_env("AIBRAIN_DB_POOL_SIZE", "5") |> String.to_integer(),
  queue_target: System.get_env("AIBRAIN_DB_QUEUE_TARGET_MS", "5000") |> String.to_integer()

# Production port — AIBRAIN_PORT env or 43225
config :ai_brain, :port, System.get_env("AIBRAIN_PORT", "43225") |> String.to_integer()

# Production workspace path
config :ai_brain, :workspace_path, System.get_env("AIBRAIN_WORKSPACE", System.user_home!())
