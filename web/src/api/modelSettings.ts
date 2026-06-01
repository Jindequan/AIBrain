import { request } from './client'

// ── Types ──────────────────────────────────────────────────

export interface CatalogProvider {
  id: string
  name: string
  base_url?: string
  env_key?: string
}

export interface CatalogModel {
  id: string
  name: string
  full_id: string
  provider: string
  context_length?: number
  max_output_tokens?: number
  input_modalities: string[]
  output_modalities: string[]
  description: string
}

export interface MyProvider {
  id: string
  name: string
  enabled: boolean
  base_url?: string
  env_key?: string
  has_key: boolean
  custom: boolean
  priority: number
}

export interface MyModel {
  id: string
  name: string
  full_id: string
  provider: string
  context_length?: number
  max_output_tokens?: number
  input_modalities: string[]
  output_modalities: string[]
  description: string
  enabled: boolean
  default: boolean
}

export interface MyModelsResponse {
  providers: MyProvider[]
  models: MyModel[]
  default_model: string | null
  setup_required: boolean
}

export interface ProviderModelsResponse {
  ok: boolean
  provider: string
  models: (CatalogModel & { enabled: boolean; default: boolean })[]
}

// ── Catalog API (read-only LLMDB) ─────────────────────────

export const catalogApi = {
  listProviders: (signal?: AbortSignal) =>
    request<{ providers: CatalogProvider[] }>('/api/v1/catalog/providers', { signal }),

  listModels: (providerId: string, signal?: AbortSignal) =>
    request<ProviderModelsResponse>(
      `/api/v1/catalog/providers/${encodeURIComponent(providerId)}/models`,
      { signal }
    ),

  refresh: () =>
    request<{ ok: true }>('/api/v1/catalog/refresh', { method: 'POST' }),
}

// ── My Models API (user config) ───────────────────────────

export const myModelsApi = {
  get: (signal?: AbortSignal) =>
    request<MyModelsResponse>('/api/v1/my-models', { signal }),

  enableModel: (provider: string, model: string) =>
    request<{ ok: boolean; provider: string; model: string; enabled: true }>(
      `/api/v1/my-models/models/${encodeURIComponent(provider)}/${encodeURIComponent(model)}`,
      { method: 'PUT' }
    ),

  disableModel: (provider: string, model: string) =>
    request<{ ok: boolean; provider: string; model: string; enabled: false }>(
      `/api/v1/my-models/models/${encodeURIComponent(provider)}/${encodeURIComponent(model)}`,
      { method: 'DELETE' }
    ),

  setDefault: (provider: string, model: string) =>
    request<{ ok: boolean; provider: string; model: string }>('/api/v1/my-models/default', {
      method: 'PUT',
      body: JSON.stringify({ provider, model }),
    }),

  configureProvider: (id: string, params: { enabled: boolean; base_url?: string; priority?: number }) =>
    request<{ ok: boolean; id: string }>(
      `/api/v1/my-models/providers/${encodeURIComponent(id)}`,
      { method: 'PATCH', body: JSON.stringify(params) }
    ),

  storeCredential: (provider: string, api_key: string) =>
    request<{ ok: boolean; provider: string }>('/api/v1/my-models/credentials', {
      method: 'POST',
      body: JSON.stringify({ provider, api_key }),
    }),

  deleteProvider: (id: string) =>
    request<{ ok: boolean; id: string }>(
      `/api/v1/my-models/providers/${encodeURIComponent(id)}`,
      { method: 'DELETE' }
    ),

  // Convenience: per-provider models with enabled/default state merged from user config
  fetchProviderModels: (providerId: string) =>
    request<ProviderModelsResponse>(
      `/api/v1/providers/${encodeURIComponent(providerId)}/models`
    ),
}
