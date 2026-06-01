import { request } from './client'

export const proxyApi = {
  status: () =>
    request<{ active: boolean; autonomy: boolean; name: string }>('/api/v1/proxy'),

  toggle: (active: boolean, autonomy?: boolean) =>
    request<{ active: boolean; autonomy: boolean }>('/api/v1/proxy/toggle', {
      method: 'POST',
      body: JSON.stringify({ active, autonomy: autonomy || false }),
    }),
}
