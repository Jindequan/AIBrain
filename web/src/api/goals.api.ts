import { request } from './client'

export interface Goal {
  id: string
  parent_id?: string
  title: string
  description?: string
  status: string
  priority: number
  metadata: Record<string, unknown>
  automation?: {
    autonomous: boolean
    autonomy_level: number
    [key: string]: unknown
  }
  strategy?: {
    assessment?: string
    current_assessment?: string
    next_actions?: string[]
    blockers?: string[]
    [key: string]: unknown
  }
  workspace_path?: string
  inserted_at: string
  updated_at: string
}

export const goalsApi = {
  list: (params?: { parent_id?: string; status?: string }) =>
    request<{ goals: Goal[] }>('/api/v1/goals', { params }),

  get: (id: string) =>
    request<Goal>(`/api/v1/goals/${id}`),

  create: (params: {
    title: string
    description?: string
    status?: string
    priority?: number
    parent_id?: string
    workspace_path?: string
    metadata?: Record<string, unknown>
  }) =>
    request<Goal>('/api/v1/goals', {
      method: 'POST',
      body: JSON.stringify(params),
    }),

  update: (id: string, params: {
    title?: string
    description?: string
    status?: string
    priority?: number
    workspace_path?: string
    metadata?: Record<string, unknown>
  }) =>
    request<Goal>(`/api/v1/goals/${id}`, {
      method: 'PUT',
      body: JSON.stringify(params),
    }),

  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/goals/${id}`, { method: 'DELETE' }),

  scan: () =>
    request<{ ok: boolean; started_run_ids: string[] }>('/api/v1/goals/scan', { method: 'POST' }),

  getEvents: (id: string) =>
    request<{ events: unknown[] }>(`/api/v1/goals/${id}/events`),

  getRuns: (id: string) =>
    request<{ runs: unknown[] }>(`/api/v1/goals/${id}/runs`),

  getMemories: (id: string) =>
    request<{ memories: unknown[] }>(`/api/v1/goals/${id}/memories`),
}
