import Config

config :ai_brain,
  ecto_repos: [AIBrain.Repo]

config :ai_brain, AIBrain.Repo,
  database: Path.expand("~/.aibrain/brain.db"),
  pool_size: System.get_env("AIBRAIN_DB_POOL_SIZE", "5") |> String.to_integer(),
  pragma: [
    journal_mode: :wal,
    cache_size: -64_000,
    foreign_keys: 1,
    busy_timeout: System.get_env("AIBRAIN_DB_BUSY_TIMEOUT_MS", "5000") |> String.to_integer()
  ]

config :ai_brain, :session_store, AIBrain.Session.Store.SQLite
config :ai_brain, :max_read_lines, 500
config :ai_brain, :default_model, "default"

config :ai_brain,
       :http_max_body_bytes,
       System.get_env("AIBRAIN_HTTP_MAX_BODY_BYTES", "10000000") |> String.to_integer()

config :ai_brain,
       :query_rate_limit_max_requests,
       System.get_env("AIBRAIN_QUERY_RATE_LIMIT_MAX", "30") |> String.to_integer()

config :ai_brain,
       :query_rate_limit_window_ms,
       System.get_env("AIBRAIN_QUERY_RATE_LIMIT_WINDOW_MS", "60000") |> String.to_integer()

config :ai_brain,
       :websocket_timeout_ms,
       System.get_env("AIBRAIN_WEBSOCKET_TIMEOUT_MS", "60000") |> String.to_integer()

config :ai_brain,
       :stt_max_path_audio_bytes,
       System.get_env("AIBRAIN_STT_MAX_PATH_AUDIO_BYTES", "50000000") |> String.to_integer()

config :ai_brain,
       :stt_max_base64_audio_bytes,
       System.get_env("AIBRAIN_STT_MAX_BASE64_AUDIO_BYTES", "8000000") |> String.to_integer()

config :ai_brain,
       :stt_min_audio_bytes,
       System.get_env("AIBRAIN_STT_MIN_AUDIO_BYTES", "100") |> String.to_integer()

# Model costs per 1M tokens (input / output)
config :ai_brain, :model_costs, %{
  "deepseek-v4-flash" => %{input: 0.05, output: 0.10},
  "claude-haiku-4-5" => %{input: 0.80, output: 4.00},
  "claude-sonnet-4-6" => %{input: 3.00, output: 15.00}
}

# SmartRouter model tier mapping (ReqLLM "provider:model" format)
config :ai_brain, :smart_router, %{
  cheap: "deepseek:deepseek-v4-flash",
  mid: "anthropic:claude-haiku-4-5",
  strong: "anthropic:claude-sonnet-4-6",
  best: "anthropic:claude-sonnet-4-6"
}

# ReqLLM Configuration
config :req_llm,
  # Auto-load .env files at startup (recommended for local development)
  load_dotenv: System.get_env("AIBRAIN_REQ_LLM_LOAD_DOTENV", "true") == "true",
  # Finch connection pool configuration
  finch: [
    name: AIBrain.ReqLLM.Finch,
    pools: %{
      :default => [protocols: [:http1], size: 1, count: 8]
    }
  ]

import_config "#{config_env()}.exs"
