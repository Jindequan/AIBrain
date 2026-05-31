import { request } from './client'

export interface ChannelConfig {
  id: string
  name: string
  channel_type: string
  enabled: boolean
  inserted_at: string
  bot_token?: string
  application_id?: string
  app_id?: string
  app_secret?: string
  webhook_secret?: string
  chat_id?: string
}

export interface ChannelConfigListResponse {
  configs: ChannelConfig[]
  channel_type?: string
}

export const channelsApi = {
  list: (channelType?: string) =>
    request<ChannelConfigListResponse>('/api/v1/channels/configs', {
      params: channelType ? { channel_type: channelType } : undefined,
    }),

  create: (body: Record<string, unknown>) =>
    request<{ ok: boolean; id: string }>('/api/v1/channels/configs', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  update: (id: string, body: Record<string, unknown>) =>
    request<{ ok: boolean }>(`/api/v1/channels/configs/${encodeURIComponent(id)}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  remove: (id: string) =>
    request<{ ok: boolean }>(`/api/v1/channels/configs/${encodeURIComponent(id)}`, {
      method: 'DELETE',
    }),
}
