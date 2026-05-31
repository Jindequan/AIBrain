// ======== Core Entities ========

export interface ToolCall {
  id?: string
  name: string
  input: object
  output?: string | null
  status?: "running" | "success" | "error"
}

export interface Artifact {
  id: string;
  run_id?: string;
  kind: "file" | "url" | "note" | "document" | "image" | "code_diff" | "email_draft" | "calendar_event" | "other";
  title: string;
  uri?: string;
  content?: string;
  content_hash?: string;
  mime_type?: string;
  metadata: Record<string, unknown>;
  inserted_at: string;
  updated_at: string;
}

export interface AutomationRule {
  id: string;
  name: string;
  description?: string;
  trigger_type: "cron" | "time" | "event" | "condition" | "manual";
  trigger_config: Record<string, unknown>;
  action: Record<string, unknown>;
  status: "active" | "paused" | "disabled" | "archived";
  risk_level: "low" | "medium" | "high" | "critical";
  confirmation_policy: "never" | "ask_for_write" | "always" | "disabled";
  last_run_at?: string;
  next_run_at?: string;
  inserted_at: string;
  updated_at: string;
}

export interface ContextLink {
  id: string;
  owner_type: "run";
  owner_id: string;
  target_type: "knowledge_entry" | "artifact" | "session" | "file" | "url" | "person" | "freeform";
  target_id?: string;
  uri?: string;
  title?: string;
  summary?: string;
  relevance: number;
  metadata: Record<string, unknown>;
  inserted_at: string;
  updated_at: string;
}

// ======== Provider & System Entities ========

export interface ModelConfig {
  name?: string
  provider?: string
  max_tokens?: number
  temperature?: number
  [key: string]: unknown
}

export interface ModelInfo {
  enabled: boolean;
  context_window?: number | null;
  max_output_tokens?: number | null;
  type?: string;
  types?: string[];
  input_modalities?: string[];
  output_modalities?: string[];
  description?: string;
  source?: string; // "fetched" | "manual"
}

export interface Provider {
  name: string;
  configured: boolean;
  api_key: string | null;
  base_url: string;
  chat_url: string;
  fetch_models_url: string | null;
  priority: number;
  enabled: boolean;
  models: Record<string, ModelInfo>;
  enabled_models?: string[]; // derived, for backward compat
  supports_model_fetch: boolean;
}

export interface CachedModel {
  id: string;
  name: string;
  type: string;
  types?: string[];
  input_modalities?: string[];
  output_modalities?: string[];
  supported_parameters?: string[];
  context_window: number;
  description?: string;
}

export interface SchedulerItem {
  id: string;
  type: string;
  trigger_at?: string;
  cron_expression?: string;
  next_fire_at?: string;
  action: string;
  status: string;
  created_at: string;
  metadata: Record<string, unknown>;
}

export interface BackgroundTask {
  id: string;
  type: "shell";
  status: "running" | "completed" | "failed";
  description?: string;
  command: string;
  cwd: string;
  created_at: string;
  started_at?: string;
  ended_at?: string;
  exit_code?: number;
  metadata: Record<string, unknown>;
}

// ======== Session & Message ========

export interface Session {
  session_id: string;
  title?: string;
  messages?: MessageData[];
  message_count?: number;
  status?: string;
  requested_model?: string;
  workspace_path?: string;
  metadata?: Record<string, unknown>;
  created_at?: string;
  updated_at?: string;
}

export interface MessageData {
  id?: string;
  role: "user" | "assistant" | "system";
  content: ContentBlock[];
  streaming?: boolean;
  error?: boolean;
  system?: boolean;
  system_type?: string;
  metadata?: Record<string, unknown>;
}

export type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } }
  | { type: "tool_use"; id: string; name: string; input: object; output?: string | null; status?: "running" | "success" | "error" }
  | { type: "thinking"; thinking_index: number; text: string; signature?: string };

// ======== WebSocket Event Types ========

export interface WsQueryRequest {
  message?: string;
  messages?: MessageData[];
  model?: string;
  session_id?: string;
  workspace_path?: string;
}

// Known SSE/WebSocket event names and data types
export interface WsTextDeltaData {
  text: string
}

export interface WsThinkingStartData {
  thinking_index: number
}

export interface WsThinkingDeltaData {
  thinking_index: number
  text: string
}

export interface WsToolStartData {
  tool_name: string
  tool_use_id: string
  input?: object
}

export interface WsToolResultData {
  tool_use_id: string
  output: string
  status: "success" | "error"
}

export interface WsToolErrorData {
  tool_use_id: string
  tool_name?: string
  message?: string
  reason?: string
  status: "error"
}

export interface WsSandboxFeedbackData {
  tool_use_id: string
  operation: string
}

export interface WsProviderData {
  provider_name: string
  retry_at?: number
  raw_error?: string
  reason?: string
}

export interface WsQueryFailedData {
  raw_error?: string
  error?: string
  reason?: string
}

export interface WsContextTruncatedData {
  dropped_count: number
}

export interface WsSessionTitleData {
  title: string
}

export interface WsEventBase {
  type: "event"
  event: string
  data: unknown
}

export interface WsTextDelta extends WsEventBase {
  event: "text_delta";
  data: WsTextDeltaData;
}

export interface WsToolStart extends WsEventBase {
  event: "tool_start";
  data: WsToolStartData;
}

export interface WsToolResult extends WsEventBase {
  event: "tool_result";
  data: WsToolResultData;
}

export interface WsResponse {
  type: "response";
  success: boolean;
  text: string;
}

export interface WsError {
  type: "error";
  error: string;
}

export interface WsSuspended {
  type: "suspended"
  data?: {
    interaction_id: string
  }
}

export interface WsDisconnected {
  type: "ws_disconnected"
}

export interface WsReconnected {
  type: "ws_reconnected"
}

export interface WsMonitorNotification {
  type: "monitor_notification";
  event: "monitor_result";
  data: {
    monitor_id: string;
    name: string;
    result: string;
    started_at: string;
    completed_at: string;
  };
}

export type WsMessage = WsEventBase | WsResponse | WsError | WsSuspended | WsDisconnected | WsReconnected | WsMonitorNotification;

// ======== REST API Responses ========

export interface ApiResponse<T> {
  data?: T;
  error?: string;
}

export interface SessionsListResponse {
  sessions: Session[];
}

export interface SessionDetailResponse extends Session {
  messages: MessageData[];
}

export interface ProvidersListResponse {
  providers: Provider[];
}

export interface TasksListResponse {
  tasks: BackgroundTask[];
}

export interface FsResponse {
  path: string;
  parent: string;
  dirs: { name: string; path: string }[];
  files?: { name: string; path: string; size?: number; mtime?: string }[];
}

// ======== User System ========

export interface User {
  id: string;
  name: string;
  bio: string | null;
  role: string;
  active: boolean;
  profile: string | null;
  preferences: Record<string, unknown>;
  inserted_at: string;
  updated_at: string;
}

// ======== Interaction System ========

export interface Interaction {
  id: string
  type: 'confirm' | 'select' | 'text_input' | 'form'
  status: 'pending' | 'proxy_running' | 'need_manual' | 'resolved' | 'expired' | 'cancelled'
  schema_data: InteractionSchema
  context: InteractionContext
  result?: InteractionResult
  proxy_trail?: Array<{
    action: string
    reasoning?: string
    prompt_versions?: string[]
  }>
  resolved_by?: 'proxy' | 'user'
  resume_token?: string
  expires_at: string
  inserted_at: string
  updated_at: string
}

export interface InteractionSchema {
  title: string
  prompt: string
  fields?: InteractionField[]
  options?: string[]  // for select type
}

export interface InteractionField {
  key: string
  label: string
  type: 'text' | 'select'
  required: boolean
  options?: string[]
}

export interface InteractionContext {
  source: string
  session_id: string
  run_id?: string
  [key: string]: any
}

export interface InteractionResult {
  decision?: 'approved' | 'denied'
  text?: string
  selected_index?: number
  form?: Record<string, any>
}

export interface InteractionResolveRequest {
  result: InteractionResult
}

// WebSocket Event Types
export interface InteractionNeededEvent {
  type: 'interaction_needed'
  interaction_id: string
  interaction_type: 'confirm' | 'select' | 'text_input' | 'form'
  schema: InteractionSchema
  context: InteractionContext
}

export interface InteractionResolvedEvent {
  type: 'interaction_resolved'
  interaction_id: string
  result: InteractionResult
  resolved_by: 'proxy' | 'user'
}

export interface InteractionEscalatedEvent {
  type: 'interaction_escalated'
  interaction_id: string
  reason: string
}
