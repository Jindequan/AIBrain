import { request } from './client'

export interface Workspace {
  id: string
  name: string
  path: string
  inserted_at: string
  updated_at: string
}

export const workspacesApi = {
  list: () =>
    request<{ workspaces: Workspace[] }>('/api/v1/workspaces'),

  get: (id: string) =>
    request<{ workspace: Workspace }>(`/api/v1/workspaces/${id}`),
}
