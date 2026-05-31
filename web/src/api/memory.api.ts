import { request } from './client'

export interface MemoryEntry {
  id: string
  type: 'fact' | 'preference' | 'learning' | 'task_outcome'
  content: string
  tags: string[]
  confidence: number
  source_session_id: string
  source_detail?: string
  usable_for_auto_decision?: boolean
  last_confirmed_at?: string
  created_at: string
}

export const memoryApi = {
  list: (type?: string) => {
    const params = type ? `?type=${encodeURIComponent(type)}` : ''
    return request<{ entries: MemoryEntry[] }>(`/api/v1/memory${params}`)
  },
  get: (id: string) => request<MemoryEntry>(`/api/v1/memory/${id}`),
  create: (body: { type: string; content: string; tags?: string[]; confidence?: number; source_detail?: string }) =>
    request<MemoryEntry>('/api/v1/memory', { method: 'POST', body: JSON.stringify(body) }),
  update: (id: string, body: Partial<Pick<MemoryEntry, 'usable_for_auto_decision' | 'source_detail' | 'confidence'>>) =>
    request<MemoryEntry>(`/api/v1/memory/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  delete: (id: string) =>
    request<{ message: string }>(`/api/v1/memory/${id}`, { method: 'DELETE' }),
}
