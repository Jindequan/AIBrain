import { request } from './client'
import type { SessionsListResponse, SessionDetailResponse } from '../models/types'

export const sessionsApi = {
  list: (params?: { offset?: string; limit?: string; search?: string; sort?: string; channel_adapter?: string; channel_id?: string; workspace_path?: string }) =>
    request<SessionsListResponse & { total?: number; offset?: number; limit?: number }>('/api/v1/sessions', { params }),

  get: (id: string, params?: { include_messages?: boolean }) =>
    request<SessionDetailResponse>(`/api/v1/sessions/${id}`, {
      params: params?.include_messages ? { include_messages: 'true' } : undefined,
    }),

  getMessages: (id: string, params?: { limit?: number; before?: number }) =>
    request<{ messages: any[]; total: number; has_more: boolean }>(`/api/v1/sessions/${id}/messages`, { params }),

  deleteMessage: (sessionId: string, messageId: string) =>
    request<{ success: boolean }>(`/api/v1/sessions/${sessionId}/messages/${messageId}`, {
      method: 'DELETE',
    }),

  truncateMessages: (sessionId: string, fromIndex: number) =>
    request<{ success: boolean; kept: number; removed: number }>(`/api/v1/sessions/${sessionId}/messages/truncate`, {
      method: 'POST',
      body: JSON.stringify({ from_index: fromIndex }),
    }),

  create: (body?: { workspace_path?: string; model?: string }) =>
    request<{ session_id: string; title: string }>('/api/v1/sessions', {
      method: 'POST',
      body: JSON.stringify(body || {}),
    }),

  update: (id: string, body: { title?: string }) =>
    request<{ session_id: string; title: string }>(`/api/v1/sessions/${id}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  delete: (id: string) =>
    request<{ message: string; session_id: string }>(`/api/v1/sessions/${id}`, { method: 'DELETE' }),

  resume: (id: string, model?: string) =>
    request<{ success: boolean; response: string; session_id: string }>(`/api/v1/sessions/${id}/resume`, {
      method: 'POST',
      body: JSON.stringify({ model }),
    }),

  stop: (id: string) =>
    request<{ status: string; session_id: string }>(`/api/v1/sessions/${id}/stop`, {
      method: 'POST',
    }),

  search: (id: string, q: string) =>
    request<{ query: string; session_id: string; matches: Array<{ message_index: number; role: string; hits: string[] }>; total: number }>(
      `/api/v1/sessions/${id}/search`,
      { params: { q } }
    ),
}
