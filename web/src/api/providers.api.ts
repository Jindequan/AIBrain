import { request } from './client'
import type { CachedModel, ProvidersListResponse } from '../models/types'

export const providersApi = {
  list: () => request<ProvidersListResponse>('/api/v1/providers'),

  add: (body: Record<string, unknown>) =>
    request<{ ok: boolean; name: string }>('/api/v1/providers', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  update: (name: string, body: Record<string, unknown>) =>
    request<{ ok: boolean }>(`/api/v1/providers/${encodeURIComponent(name)}`, {
      method: 'PUT',
      body: JSON.stringify(body),
    }),

  delete: (name: string) =>
    request<{ ok: boolean }>(`/api/v1/providers/${encodeURIComponent(name)}`, { method: 'DELETE' }),

  enable: (name: string) =>
    request<{ ok: boolean }>(`/api/v1/providers/${encodeURIComponent(name)}/enable`, { method: 'POST' }),

  disable: (name: string) =>
    request<{ ok: boolean }>(`/api/v1/providers/${encodeURIComponent(name)}/disable`, { method: 'POST' }),

  fetchModels: (name: string, body?: Record<string, unknown>) =>
    request<{ ok: boolean; provider: string; created: number }>(
      `/api/v1/providers/${encodeURIComponent(name)}/fetch_models`,
      { method: 'POST', ...(body ? { body: JSON.stringify(body) } : {}) },
    ),

  listModels: (name: string) =>
    request<{ ok: boolean; provider: string; models: CachedModel[] }>(
      `/api/v1/providers/${encodeURIComponent(name)}/models`,
    ),

  fetchAllModels: () =>
    request<{ ok: boolean; count: number }>('/api/v1/models/fetch', { method: 'POST' }),

  listProviderModels: (provider: string) =>
    request<{ ok: boolean; provider: string; models: CachedModel[] }>(
      '/api/v1/models?provider=' + encodeURIComponent(provider),
    ),

  listAllModels: () =>
    request<{ models: Array<{
      provider: string
      name: string
      type: string
      types?: string[]
      input_modalities?: string[]
      output_modalities?: string[]
      supported_parameters?: string[]
      context_window?: number
      description?: string
      enabled: boolean
      is_default_category: string | null
      icon_url?: string
    }> }>('/api/v1/models/all'),

  getDefaultModels: () =>
    request<Record<string, { provider: string; model: string } | null>>('/api/v1/system/default_models'),

  setDefaultModel: (provider: string, model: string, category: string) =>
    request<{ ok: boolean }>('/api/v1/system/default_model', {
      method: 'PUT',
      body: JSON.stringify({ provider, model, category }),
    }),

  listOpenRouterProviders: () =>
    request<{ providers: Array<{ name: string; display_name: string; icon?: string }> }>(
      '/api/v1/providers/openrouter',
    ),

  fetchOpenRouterProviders: () =>
    request<{ ok: boolean; count: number }>('/api/v1/providers/openrouter/fetch', { method: 'POST' }),
}
