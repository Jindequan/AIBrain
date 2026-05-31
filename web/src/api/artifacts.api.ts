import { request } from './client'

export const artifactsApi = {
  list: (params?: { kind?: string }) =>
    request<{ artifacts: any[] }>('/api/v1/artifacts', { params: params as Record<string, string> }),

  get: (id: string) =>
    request<{ artifact: any }>(`/api/v1/artifacts/${id}`),

  create: (body: any) =>
    request<{ artifact: any }>('/api/v1/artifacts', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  update: (id: string, body: any) =>
    request<{ artifact: any }>(`/api/v1/artifacts/${id}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/artifacts/${id}`, { method: 'DELETE' }),
}
