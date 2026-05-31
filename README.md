# AIBrain

> Self-hosted AI assistant with tool-calling, skills, and autonomous agents — built with Elixir and React.

## Features

- **Multi-turn chat** with streaming SSE & WebSocket
- **Tool system** — bash, file read/write/edit, web search, image generation, and custom tools
- **Skill-driven architecture** — loadable AI skills for extensible capabilities
- **Autonomous agent runtime** with approval workflows and configurable autonomy levels
- **Goal & task management** with cron scheduling and progress tracking
- **Multi-provider support** — OpenAI, Anthropic, Google Gemini, DeepSeek, OpenRouter, Ollama, and more
- **Memory & RAG** — conversation distillation, knowledge graph, retrieval-augmented generation
- **Multi-channel** — Web, Telegram, Discord, WeChat, WhatsApp
- **SQLite** — zero external database dependencies, runs anywhere

## Quick Start

### Prerequisites

- Elixir 1.19+
- Node.js 22+
- (optional) a provider API key: OpenAI, Anthropic, or OpenRouter

### Setup & Run

```sh
make setup    # install dependencies, initialize database
make dev      # start server (port 4100) + web (port 5200)
```

Open `http://localhost:5200`. Configure a provider and API key on the Providers page to start chatting.

## Architecture

```
AIBrain/
├── server/          # Elixir backend — Plug.Router + SQLite
│   ├── lib/ai_brain/agent_runtime/  # Orchestrator, run lifecycle, authorization
│   ├── lib/ai_brain/llm/            # Provider management, streaming client
│   ├── lib/ai_brain/tool/           # Built-in tools (bash, file, web, image)
│   ├── lib/ai_brain/skill/          # Skill registry and manager
│   ├── lib/ai_brain/web/            # HTTP API, WebSocket, SSE streaming
│   └── lib/ai_brain/memory/         # Semantic memory, conversation distillation
├── web/             # React frontend — Vite + Zustand + Tailwind
│   └── src/pages/   # Chat, Providers, Runs, Goals, Settings, Memory...
├── docs/            # Architecture documentation
└── scripts/         # Development helper scripts
```

See `docs/architecture.md` for a detailed walkthrough of the system design.

## Contributing

See `CONTRIBUTING.md` for guidelines. Pull requests are welcome.

## License

AIBrain is free software licensed under the [GNU Affero General Public License v3.0](LICENSE).

If you use AIBrain to provide a network service, you must make the source code available to users of that service.
