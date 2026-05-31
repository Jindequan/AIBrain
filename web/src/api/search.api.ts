import { request } from './client'

export interface SearchResult {
  type: 'session' | 'goal' | 'task' | 'artifact'
  id: string
  title: string
  subtitle?: string | null
  status?: string
  kind?: string
  url: string
}

export interface GlobalSearchResponse {
  results: SearchResult[]
  total: number
}

export const searchApi = {
  globalSearch: (q: string) =>
    request<GlobalSearchResponse>('/api/v1/search', { params: { q } }),
}
