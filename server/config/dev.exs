import Config

config :ai_brain, AIBrain.Repo, database: Path.expand("~/.aibrain/brain.db")

# 工作目录配置 - AI 执行 bash 命令的当前工作目录（cwd）
# 可通过 AIBRAIN_WORKSPACE 环境变量覆盖
# 不设默认值：没选工作空间时 AI 无文件访问权限
config :ai_brain, :workspace_path, System.get_env("AIBRAIN_WORKSPACE")
config :ai_brain, :wiki_path, ".aibrain/knowledge_wiki"

config :ai_brain, :session_store, AIBrain.Session.Store.SQLite

config :ai_brain, :disable_http, false
config :ai_brain, :port, 4100

config :ai_brain, :dev_reloader, true

config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:trace_id, :module, :line]

# Set level to :info to reduce noise, :warning for only warnings+errors
# config :logger, level: :info
# config :logger, level: :warning

# 通知网关适配器配置（可选）
# 每个适配器需要对应的认证凭据，取消注释需要启用的即可
# config :ai_brain, :gateway_adapters, [
#   # Telegram
#   {AIBrain.Channel.Adapters.TelegramAdapter,
#    bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
#    chat_id: System.get_env("TELEGRAM_CHAT_ID")},
#   # Discord
#   {AIBrain.Channel.Adapters.DiscordAdapter,
#    bot_token: System.get_env("DISCORD_BOT_TOKEN"),
#    application_id: System.get_env("DISCORD_APPLICATION_ID")},
#   # Feishu
#   {AIBrain.Channel.Adapters.FeishuAdapter,
#    app_id: System.get_env("FEISHU_APP_ID"),
#    app_secret: System.get_env("FEISHU_APP_SECRET")},
#   # WeChat (需要 bridge: wechaty/itchat)
#   {AIBrain.Channel.Adapters.WechatAdapter,
#    webhook_secret: System.get_env("WECHAT_WEBHOOK_SECRET")},
#   # WhatsApp (需要 bridge: whatsapp-web.js)
#   {AIBrain.Channel.Adapters.WhatsappAdapter,
#    webhook_secret: System.get_env("WHATSAPP_WEBHOOK_SECRET")}
# ]

# 文件监控目录配置（可选）
# config :ai_brain, :watched_dirs, [
#   Path.join(System.user_home!(), "Downloads"),
#   Path.join(System.user_home!(), "Desktop")
# ]
