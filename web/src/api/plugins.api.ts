import { request } from './client'

export const pluginsApi = {
  list: () => request<{ plugins: any[] }>('/api/v1/plugins'),
  get: (name: string) => request<{ plugin: any }>(`/api/v1/plugins/${name}`),
  install: (url: string) =>
    request<{ plugin: any; message: string }>('/api/v1/plugins/install', {
      method: 'POST',
      body: JSON.stringify({ url }),
    }),
  installLocal: (path: string) =>
    request<{ plugin: any; message: string }>('/api/v1/plugins/install', {
      method: 'POST',
      body: JSON.stringify({ path }),
    }),
  enable: (name: string) =>
    request<{ plugin: any; message: string }>(`/api/v1/plugins/${name}/enable`, { method: 'POST' }),
  disable: (name: string) =>
    request<{ plugin: any; message: string }>(`/api/v1/plugins/${name}/disable`, { method: 'POST' }),
  uninstall: (name: string) =>
    request<{ message: string }>(`/api/v1/plugins/${name}/uninstall`, { method: 'POST' }),
  update: (name: string) =>
    request<{ plugin: any; message: string }>(`/api/v1/plugins/${name}/update`, { method: 'POST' }),
}
