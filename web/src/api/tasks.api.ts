import { request } from './client'

export interface GoalTask {
  id: string
  goal_id: string
  parent_id?: string
  title: string
  description?: string
  status: string
  priority: number
  required_skills?: string[]
  depends_on?: string[]
  output?: string
  run_id?: string
  workspace_path?: string
  autonomy_level?: number
  schedule_id?: string
  metadata: Record<string, unknown>
  inserted_at: string
  updated_at: string
}

export const tasksApi = {
  listAll: () =>
    request<{ tasks: GoalTask[] }>('/api/v1/tasks'),

  listByGoal: (goalId: string) =>
    request<{ tasks: GoalTask[] }>(`/api/v1/goals/${goalId}/tasks`),

  get: (id: string) =>
    request<GoalTask>(`/api/v1/tasks/${id}`),

  getEvents: (id: string) =>
    request<{ events: unknown[] }>(`/api/v1/tasks/${id}/events`),
}
