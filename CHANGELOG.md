# Changelog

## v1.0.0 (unreleased)

Initial public release.

### Core
- Multi-turn chat with SSE streaming and WebSocket
- Autonomous agent runtime with configurable autonomy levels
- Approval workflow for tool execution
- Run lifecycle management (pending → running → completed/failed/cancelled)

### Tools
- Bash sandbox with path validation
- File read, write, and semantic edit
- Web search via provider APIs
- Image generation

### Skills
- Skill-driven architecture with loadable skill definitions
- Skill registry with hot-reload support

### Providers
- Multi-provider support via ReqLLM (26+ providers)
- Provider configuration with API key management
- Per-provider model enable/disable
- Default model per category (lite, normal, image, video, audio)

### Memory
- Conversation distillation to knowledge graph
- Semantic memory extraction
- Episodic memory with goal association

### Channels
- Web UI (React + Vite)
- Telegram, Discord, WeChat, WhatsApp webhooks

### Scheduling
- Cron-based automation rules
- Goal daemon for continuous task execution
- Monitor system for recurring checks
