// frontend/src/api/interactions.api.ts
import { request } from './client'
import type { Interaction, InteractionResolveRequest } from '../models/types'

export const interactionsApi = {
  // List interactions with optional filters
  list: (params?: { status?: string; session_id?: string }) => {
    const queryParams = new URLSearchParams()
    if (params?.status) queryParams.set('status', params.status)
    if (params?.session_id) queryParams.set('session_id', params.session_id)

    const qs = queryParams.toString()
    return request<{ interactions: Interaction[] }>(
      `/api/v1/interactions${qs ? `?${qs}` : ''}`
    )
  },

  // Get single interaction by ID
  get: (id: string) =>
    request<{ interaction: Interaction }>(`/api/v1/interactions/${id}`),

  // Resolve an interaction (user action)
  resolve: (id: string, body: InteractionResolveRequest) =>
    request<{ status: 'ok' }>(`/api/v1/interactions/${id}/resolve`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  // Stop proxy processing (user takes control)
  stopProxy: (id: string) =>
    request<{ status: 'stopped' }>(`/api/v1/interactions/${id}/stop_proxy`, {
      method: 'POST',
    }),

  // Get interactions for a specific session
  getBySession: (sessionId: string) =>
    request<{ interactions: Interaction[] }>(
      `/api/v1/sessions/${sessionId}/interactions`
    ),
}
