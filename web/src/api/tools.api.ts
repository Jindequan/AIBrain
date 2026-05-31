import { request } from './client'

export const toolsApi = {
  list: () => request<{ tools: any[] }>('/api/v1/tools'),
}
