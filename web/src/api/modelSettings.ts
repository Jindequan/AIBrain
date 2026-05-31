import { request } from './client'

// Model settings types (matching backend ModelSettingsViewModel)
export interface ProviderSettings {
  id: string
  name: string
  enabled: boolean
  base_url?: string
  env_key?: string
  has_key: boolean
  custom: boolean
  provider_type: string
  updated_at?: string
}

export interface ModelSettings {
  id: string           // "provider:model_name"
  name: string
  provider: string
  context_length?: number
  max_output_tokens?: number
  input_modalities: string[]
  output_modalities: string[]
  description: string
  enabled: boolean
  default: boolean
}

export interface ModelSettingsViewModel {
  providers: ProviderSettings[]
  enabled_models: string[] | ':all'   // ':all' means all models enabled unless disabled
  disabled_models: string[]            // models explicitly disabled by user
  default_model: string | null
  setup_required: boolean
  catalog: {
    source: string
    provider_count: number
    model_count: number
    refreshed_at: string | null
  }
}

export const modelSettingsApi = {
  get: (signal?: AbortSignal) =>
    request<ModelSettingsViewModel>('/api/v1/model-settings', { signal }),

  configureProvider: (body: {
    name: string; enabled: boolean; base_url?: string;
    custom?: boolean; provider_type?: string;
  }) =>
    request<ModelSettingsViewModel>('/api/v1/settings/providers', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  storeCredential: (provider: string, api_key: string) =>
    request<ModelSettingsViewModel>('/api/v1/settings/credentials', {
      method: 'POST',
      body: JSON.stringify({ provider, api_key }),
    }),

  deleteProvider: (name: string) =>
    request<ModelSettingsViewModel>(`/api/v1/settings/providers/${encodeURIComponent(name)}`, {
      method: 'DELETE',
    }),

  updateModelPolicy: (body: { enabled_models?: string[]; disabled_models?: string[]; toggle_model?: string; enabled?: boolean; default_model?: string | null }) =>
    request<ModelSettingsViewModel>('/api/v1/settings/model-policy', {
      method: 'POST',
      body: JSON.stringify(body),
    }),

  toggleModel: (modelId: string, enabled: boolean, defaultModel?: string | null) =>
    request<ModelSettingsViewModel>('/api/v1/settings/model-policy', {
      method: 'POST',
      body: JSON.stringify({ toggle_model: modelId, enabled, default_model: defaultModel }),
    }),

  refreshCatalog: () =>
    request<ModelSettingsViewModel>('/api/v1/settings/catalog/refresh', { method: 'POST' }),

  fetchProviderModels: (providerId: string) =>
    request<{ ok: boolean; provider: string; models: ModelSettings[] }>(
      `/api/v1/providers/${encodeURIComponent(providerId)}/models`
    ),
}
