# AIBrain 全流程问题分析

> 2026-05-31 — 从每个页面的用户视角出发，串联完整流程，分析所有环节的问题。

---

## 一、Providers & Models 管理（/providers）

### 用户目标
配置 AI 提供商（API key）、管理可用模型、设置默认模型。

### 流程串接

```
ProvidersPage (React)
  ├── modelSettingsApi.get()         → GET /api/v1/model-settings
  │     └── ProvidersHandler.handle_model_settings
  │           ├── Provider.Catalog.provider_entries()  ← ReqLLM 内置列表 (26个)
  │           ├── ProviderConfig.load_config()         ← ~/.aibrain/provider_config.json
  │           ├── LLM.Provider.has_api_key?()          ← ReqLLM.get_key()
  │           └── ETS cache (:ai_brain_model_settings)
  │
  ├── modelSettingsApi.fetchProviderModels(id) → GET /api/v1/providers/:id/models
  │     └── Catalog.models_for_provider()  ← LLMDB 查询（懒加载）
  │
  ├── modelSettingsApi.configureProvider()  → POST /api/v1/settings/providers
  ├── modelSettingsApi.storeCredential()    → POST /api/v1/settings/credentials
  ├── modelSettingsApi.deleteProvider()     → DELETE /api/v1/settings/providers/:name
  ├── modelSettingsApi.updateModelPolicy()  → POST /api/v1/settings/model-policy
  │     └── 遍历全部 1330 个 catalog 模型 → 逐模型写 enabled 状态 → 写 disk
  └── modelSettingsApi.refreshCatalog()     → POST /api/v1/settings/catalog/refresh
```

### 问题清单

#### 1.1 🔴 模型切换性能灾难
`handleToggleModel` (ProvidersPage:144) → `updateModelPolicy` (providers_handler:568) 对 **全部 1330 个模型** 做 O(n) 遍历，逐个更新 `provider_config.json`，然后写回磁盘。每次切换一个模型就触发全量写入。用户每点一次 toggle，背后是遍历 1330 个条目 + JSON 序列化 + 磁盘写入。

#### 1.2 🔴 `list_models/1` 返回空列表导致默认模型回退死路
`llm/provider.ex:89-95` — `list_models` 注释说 "ReqLLM doesn't expose list_provider_models, so we return an empty list"。当用户没有设置系统默认模型时，`resolve_model("default")` 走到 fallback 分支调用 `select_provider` → `list_models` → 永远是 `{:ok, []}` → 返回 `{:error, :no_models_available}`。**没有默认模型时系统无法自动选出任何模型，用户必须手动选择。** 但 UI 上没有明确的指引告诉用户必须先去 Settings 设置默认模型。

#### 1.3 🟡 Provider 列表未按可用性排序
Providers 左侧列表显示全部 26+ provider，不论是否配置了 key。用户看到一堆灰色/黄色的状态灯，无从下手。应该把已配置 key 的 provider 排到最前面。

#### 1.4 🟡 两个重叠的 Provider API
- `GET /api/v1/providers` → `providersApi.list()` — 老接口
- `GET /api/v1/model-settings` → `modelSettingsApi.get()` — 新接口（UI 实际使用）

两者都返回 provider 列表但格式不同。老接口仍有代码引用但可能已经不一致。

#### 1.5 🟡 ModelSelector 拉取全量模型
ChatInput 里的 ModelSelector 通过 `GET /api/v1/models/all` 拉取所有 provider 的全部模型。如果有 5 个配置了 key 的 provider，可能拉取几百个模型条目，仅为了填充一个下拉选择器。

#### 1.6 🟡 每次操作读/写磁盘
`ProviderConfig.load_config()` 在每次 `enable_provider`、`disable_provider`、`set_base_url`、`enable_model`、`disable_model` 调用时都重新从磁盘读取完整 JSON 文件。provider_handler.ex 里的 `compute_and_cache()` 也每次 `load_config()`。没有进程内缓存。

#### 1.7 🟢 formatTokens(null) 可能崩溃
`ProvidersPage:11-17` — `formatTokens(n)` 在 `n` 为 `null` 时返回 `''`（提前判断 `n == null`），这个判断是对的。但随后 `n.toLocaleString()` 在 `n` 为 0 时会正常工作，不会崩溃。此问题实际不存在，我收回。

#### 1.8 🟢 Custom Provider 添加后不自动 fetch models
添加 Custom Provider（如 Ollama）后，不会自动触发 model fetch。用户需要先添加 provider、保存 key，然后无从知道怎么获取模型列表——界面上没有 "Fetch Models" 按钮。

---

## 二、Chat 对话（/chat, /sessions/:id）

### 用户目标
发送消息，获得 AI 回复，看到工具调用过程和结果。

### 流程串接

```
ChatPage
  ├── useChatWebSocket → wsStore.subscribe()
  │     └── WebSocket 事件 → EVENT_HANDLERS → chatStore
  │
  ├── useQuery(["session", id]) → GET /api/v1/sessions/:id
  │     └── 轮询 (running 时 5s)
  │
  ├── useQuery(["session-messages", id]) → GET /api/v1/sessions/:id/messages
  │     └── streaming 时 3s 轮询
  │
  ├── handleSend()
  │     ├── sessionsApi.create()           → POST /api/v1/sessions
  │     ├── uploadImage()                  → POST /api/v1/files/upload
  │     ├── sessionsApi.truncateMessages() → POST /api/v1/sessions/:id/messages/truncate
  │     ├── chatStore.addUserMessage()
  │     ├── chatStore.startStreaming()
  │     ├── wsStore.send(query)            → WebSocket → Socket.handle_query()
  │     │     └── Orchestrator.run_messages_auto()
  │     │           ├── 实时事件 → :ws_send → format_event() → WebSocket push
  │     │           └── 完成/挂起 → response/suspended/error
  │     └── SSE fallback: sseQuery()       → POST /api/v1/query/stream
  │
  └── 消息同步 useEffect (ChatPage:221-310)
        ├── messageSyncSignature() 去重检测
        ├── streaming/非streaming 状态调和
        └── recovery mode 恢复
```

### 问题清单

#### 2.1 🔴 三路消息同步的竞态地狱
消息可以同时通过三个路径到达 UI：
1. **WebSocket 实时事件** — `text_delta`, `tool_result` 等实时写入 chatStore
2. **SSE streaming** — fallback 模式，同样写入 chatStore
3. **HTTP 轮询** — `messagesData` (3s) 和 `sessionData` (5s)

`useEffect` (ChatPage:221-286) 负责将这三种来源与服务器状态调和。逻辑包括：
- `messageSyncSignature` 去重
- streaming 时跳过同步（避免覆盖实时内容）
- 错误消息保护（不覆盖用户看到的错误）
- 空服务器响应保护（不清空已有消息）
- Recovery mode 检测和进入

这个 60 行的 useEffect 是整个 Chat 系统的事实上的分布式一致性协议——协议写在一个 React hook 里，没有测试，没有形式验证。

#### 2.2 🟡 Recovery 逻辑重复
ChatPage:271-283 和 ChatPage:290-309 两个 useEffect 都在检测 "session 在运行但我们没有主动 streaming" 的状态。第一个在消息同步 effect 里检测，第二个作为独立 effect。两个 effect 可能同时触发导致状态冲突。

#### 2.3 🟡 WebSocket fallback 用户体验差
当 wsStore.send 返回 false（WebSocket 未连接），显示 "WebSocket disconnected, falling back to SSE..."，然后启动 SSE。用户看到这条消息会感到不安。应该是透明的，不显示给用户。

#### 2.4 🟡 编辑/重新生成的截断索引计算有 Bug 风险
`editTruncateIndexRef` (ChatPage:531) 计算方式：
```js
const loadedOffset = Math.max(0, (totalMessagesRef.current || msgs.length) - msgs.length);
editTruncateIndexRef.current = loadedOffset + msgIndex;
```
这里假设 `totalMessagesRef.current - msgs.length` 就是已加载偏移量。但如果消息在对话过程中被其他客户端修改，这个偏移会错位。

#### 2.5 🟡 图片上传是顺序阻塞的
`handleSend` (ChatPage:426-433) 逐个上传图片：
```js
for (const img of pendingImages) {
  try { const result = await uploadImage(img.file); ... }
  catch (err) { uploadErrors.push(err.message); }
}
```
3 张图片 = 3 次顺序 await。用户看着发送按钮等待。应该并行上传。

#### 2.6 🟢 SSE 和 WebSocket 的工具结果格式不一致
WebSocket 发送结构化 tool 事件（`tool_use_start_sse`, `tool_result` 等），SSE 通过 `onToolResult` 回调处理。两者维护两套事件解析逻辑，容易不同步。

---

## 三、Settings（/settings）

### 用户目标
管理系统配置、连接状态、集成。

### 问题清单

#### 3.1 🟡 Settings 页面几乎全静态
除了 Google OAuth 连接状态和 WebSocket 连接指示器，所有内容都是静态展示：
- API URL 和 WS URL 是只读的
- "Configure Integrations" 只是一组跳转链接
- "Save" 按钮保存到 `localStorage` 而非后端

用户期望的 Settings 是一个可以实际修改系统配置的地方，但实际只是个导航中心。

#### 3.2 🟡 Google OAuth 缺少 refresh_token 时不提示重新授权
代码 (SettingsPage:92-96) 检测了 `status.has_refresh_token` 并在缺失时显示警告，但这只发生在已连接状态。如果用户授权时没有勾选 "offline access"，应该引导用户断开并重新授权。

---

## 四、Runs（/runs）— 运行监控

### 用户目标
查看所有 AI 运行的执行状态、步骤、证据。

### 问题清单

#### 4.1 🟢 流程基本合理
页面结构清晰：左侧时间线 + 右侧详情。每 5 秒轮询，支持状态过滤。这个页面的用户体验相对较好。

---

## 五、Sessions（/sessions）— 会话管理

### 用户目标
浏览和管理所有对话会话。

### 问题清单

#### 5.1 🟢 API 设计合理
Session CRUD + pagination + search + truncate + resume + stop。覆盖全面。

---

## 六、编译器警告（阻止 --warnings-as-errors 构建）

### 6.1 🟡 `llm/provider.ex:227` — 类型警告
`resolve_model/2` 的类型推断有问题。`select_provider` 返回 `{:ok, provider} | {:error, reason}`，但在某些分支类型的推断可能不一致。

### 6.2 🟡 `memory/distiller.ex:466` — 不可达代码
`ingest_conversation` 永远返回 `{:ok, count}`，`{:error, reason}` 分支永远匹配不到。要么是类型标注错误，要么是错误处理分支无用。

### 6.3 🟡 `session_handler.ex:421` — 未使用的默认参数
私有函数 `build_session_data/2` 的 `opts \\ []` 默认值从未被使用（所有调用处都传了 opts）。

---

## 七、架构层面问题

### 7.1 🔴 新老 Provider 系统双轨运行
存在两套 provider 管理系统：
- **老的**：`Provider.Registry` (ETS GenServer) + `Provider.Info` + `FileBackend` — 仍在 `application.ex` 中启动
- **新的**：`LLM.Provider` + `ProviderConfig` + `Provider.Catalog` — 实际被 Web handlers 使用

Provider.Registry 在 `init/1` 中尝试从 ReqLLM 加载 provider，失败后 fallback 到老的 FileBackend。但 handlers 使用的是完全不同的代码路径（直接调 LLM.Provider + LLMDB）。**老系统可能已经完全不被使用但仍在启动和维护。**

### 7.2 🟡 `list_providers/0` 是硬编码列表
`llm/provider.ex:35-40` — 26 个 provider atom 硬编码。如果 ReqLLM 新增了 provider，这里需要手动更新。

### 7.3 🟡 ProviderConfig 每次操作都读/写完整 JSON 文件
没有内存缓存。`load_config()` 每次都 `File.read()` + `Jason.decode()`。`save_config()` 每次都 `Jason.encode()` + `File.write()`。多次连续操作（如批量 enable 模型）会有 N 次文件 I/O。

### 7.4 🟡 ETS 缓存手动失效
`handle_model_settings` 使用 ETS 缓存，但缓存失效全靠各 handler 手动调用 `:ets.delete(:ai_brain_model_settings, :data)`。如果忘记在某处失效，用户会看到过期数据。

---

## 八、总结优先级

| 优先级 | 问题 | 影响 |
|--------|------|------|
| 🔴 P0 | 模型 toggle O(n×1330) 性能 | 每次点 toggle 都卡 |
| 🔴 P0 | `list_models/1` 返回空 → 默认模型回退死路 | 新用户无默认模型时无法发消息 |
| 🔴 P0 | 三路消息同步竞态 | 消息丢失/重复/覆盖 |
| 🔴 P0 | 新老 Provider 系统双轨 | 维护负担，行为不一致 |
| 🟡 P1 | Provider 列表不按可用性排序 | 用户体验混乱 |
| 🟡 P1 | Recovery 逻辑重复 | 维护困难，Bug 风险 |
| 🟡 P1 | ProviderConfig 每次操作磁盘 I/O | 累积延迟 |
| 🟡 P1 | 3 个编译器警告 | 无法用 --warnings-as-errors 构建 |
| 🟡 P2 | Settings 页面几乎是静态导航 | 功能名不副实 |
| 🟡 P2 | 图片顺序上传 | 慢 |
| 🟡 P2 | Custom provider 无 Fetch Models 按钮 | 用户不知道下一步怎么做 |

---

## 附：Session 管理流程补充分析

当前 Session 的生命周期管理涉及：
- `Session.Registry` — 进程注册（防重复运行）
- `Session.Store` — 持久化存储（SQLite）
- `GoalDaemon` — 后台目标持续执行
- `Orchestrator` — Agent 循环编排

WebSocket 连接断开 → session 仍在后台运行 → 前端重连 → recovery mode 检测 → 拉取新消息。这个流程理论上可行，但 recovery mode 的进入判定依赖 React useEffect 的执行时机，不是事件驱动的。
