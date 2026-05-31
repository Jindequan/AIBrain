import { request } from './client'

export const automationRulesApi = {
  list: (params?: Record<string, string>) =>
    request<{ automation_rules: any[] }>('/api/v1/automation_rules', { params }),

  get: (id: string) =>
    request<{ automation_rule: any }>(`/api/v1/automation_rules/${id}`),

  create: (body: any) =>
    request<{ automation_rule: any }>('/api/v1/automation_rules', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  update: (id: string, body: any) =>
    request<{ automation_rule: any }>(`/api/v1/automation_rules/${id}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/automation_rules/${id}`, { method: 'DELETE' }),
}
