import { request } from './client'

export const skillsApi = {
  list: () => request<{ skills: any[] }>('/api/v1/skills'),
  get: (name: string) => request<{ skill: any }>(`/api/v1/skills/${name}`),
  create: (body: {
    name: string
    description?: string
    prompt_body?: string
    status?: string
  }) =>
    request<{ skill: any }>('/api/v1/skills', {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  update: (name: string, body: any) =>
    request<{ status: string }>(`/api/v1/skills/${name}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),
  delete: (name: string) =>
    request<{ status: string }>(`/api/v1/skills/${name}`, { method: 'DELETE' }),
  toggle: (name: string) =>
    request<{ status: string; new_status: string }>(`/api/v1/skills/${name}/toggle`, { method: 'POST' }),
}

export const runsApi = {
  list: (status?: string) =>
    request<{ runs: any[] }>(`/api/v1/runs${status ? `?status=${status}` : ''}`),
  get: (id: string) => request<{ run: any }>(`/api/v1/runs/${id}`),
  create: (task: string) =>
    request<{ run_id: string; status: string }>('/api/v1/runs', {
      method: 'POST',
      body: JSON.stringify({ objective: task, mode: 'manual' }),
    }),
  cancel: (id: string) =>
    request<{ status: string }>(`/api/v1/runs/${id}/cancel`, { method: 'POST' }),
}
