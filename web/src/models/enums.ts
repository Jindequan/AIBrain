export const ArtifactKind = {
  FILE: "file",
  URL: "url",
  NOTE: "note",
  DOCUMENT: "document",
  IMAGE: "image",
  CODE_DIFF: "code_diff",
  EMAIL_DRAFT: "email_draft",
  CALENDAR_EVENT: "calendar_event",
  OTHER: "other",
} as const;

export const AutomationRuleTrigger = {
  CRON: "cron",
  TIME: "time",
  EVENT: "event",
  CONDITION: "condition",
  MANUAL: "manual",
} as const;

export const AutomationRuleStatus = {
  ACTIVE: "active",
  PAUSED: "paused",
  DISABLED: "disabled",
  ARCHIVED: "archived",
} as const;

export const RiskLevel = {
  LOW: "low",
  MEDIUM: "medium",
  HIGH: "high",
  CRITICAL: "critical",
} as const;

export const ConfirmationPolicy = {
  NEVER: "never",
  ASK_FOR_WRITE: "ask_for_write",
  ALWAYS: "always",
  DISABLED: "disabled",
} as const;

export const TaskStatus = {
  RUNNING: "running",
  COMPLETED: "completed",
  FAILED: "failed",
} as const;

export const Priority = {
  LOWEST: 5 as const,
  LOW: 4 as const,
  MEDIUM: 3 as const,
  HIGH: 2 as const,
  HIGHEST: 1 as const,
};

export const WsEventType = {
  EVENT: "event",
  RESPONSE: "response",
  ERROR: "error",
  MONITOR_NOTIFICATION: "monitor_notification",
} as const;

export const ToolStatus = {
  RUNNING: "running",
  SUCCESS: "success",
  ERROR: "error",
  TIMEOUT: "timeout",
} as const;
