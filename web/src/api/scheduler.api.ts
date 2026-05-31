import { request } from './client'

export interface AutomationRule {
  id: string
  name: string
  trigger_type: string
  trigger_config: Record<string, unknown>
  action_type: string
  action_config: Record<string, unknown>
  status: string
  priority: number
  next_fire_at?: string
  last_fired_at?: string
  last_result?: string
  inserted_at: string
  updated_at: string
}

export const schedulerApi = {
  list: (params?: { status?: string; trigger_type?: string }) => {
    const query = new URLSearchParams()
    if (params?.status) query.set('status', params.status)
    if (params?.trigger_type) query.set('trigger_type', params.trigger_type)
    const qs = query.toString()
    return request<{ automation_rules: AutomationRule[] }>(`/api/v1/automation_rules${qs ? `?${qs}` : ''}`)
  },

  get: (id: string) =>
    request<AutomationRule>(`/api/v1/automation_rules/${id}`),

  create: (params: {
    name: string
    trigger_type: string
    trigger_config?: Record<string, unknown>
    action?: { type?: string; title?: string; message?: string; required_skills?: string[]; goal_id?: string; notify_channels?: string[] }
    status?: string
    priority?: number
  }) =>
    request<AutomationRule>('/api/v1/automation_rules', {
      method: 'POST',
      body: JSON.stringify(params),
    }),

  update: (id: string, params: {
    name?: string
    trigger_type?: string
    trigger_config?: Record<string, unknown>
    action?: { type?: string; title?: string; message?: string; required_skills?: string[]; goal_id?: string; notify_channels?: string[] }
    status?: string
    priority?: number
  }) =>
    request<AutomationRule>(`/api/v1/automation_rules/${id}`, {
      method: 'PUT',
      body: JSON.stringify(params),
    }),

  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/automation_rules/${id}`, { method: 'DELETE' }),

  getRuns: (id: string) =>
    request<{ schedule_id: string; runs: unknown[] }>(`/api/v1/automation_rules/${id}/runs`),

  scan: () =>
    request<{ ok: boolean; fired_schedule_ids: string[]; diagnostics: unknown }>('/api/v1/automation_rules/scan', { method: 'POST' }),
}
