import { request } from './client'

export interface EventRecord {
  id: string
  correlation_id: string
  event_type: string
  source: string
  channel_type?: string
  payload: Record<string, unknown>
  metadata: Record<string, unknown>
  session_id?: string
  goal_id?: string
  task_id?: string
  run_id?: string
  importance: number
  inserted_at: string
  updated_at: string
}

export const eventsApi = {
  listByGoal: (goalId: string) =>
    request<{ events: EventRecord[] }>(`/api/v1/goals/${goalId}/events`),

  listByTask: (taskId: string) =>
    request<{ events: EventRecord[] }>(`/api/v1/tasks/${taskId}/events`),
}
