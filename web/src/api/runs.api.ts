import { request } from './client'

export interface RunStep {
  step_index: number
  phase: string
  status: string
  kind: string
  title: string
  summary?: string
  error?: string
  output_path?: string
  started_at?: string
  completed_at?: string
}

export interface EvidenceItem {
  id: string
  claim: string
  source_type: string
  tool_name?: string
  source_uri?: string
  source_title?: string
  confidence: number
  status?: string
  inserted_at: string
}

export interface Verification {
  status?: string
  warnings: string[]
  failures: string[]
  unknowns: string[]
}

export interface Run {
  id: string
  run_id: string
  source_type: string
  source_id?: string
  status: string
  phase?: string
  mode?: string
  title?: string
  objective?: string
  autonomy_level?: number
  workspace_path?: string
  messages_path?: string
  output_path?: string
  output_summary?: string
  error?: string
  parent_run_id?: string
  metadata?: Record<string, unknown>
  deliverables?: unknown[]
  started_at?: string
  completed_at?: string
  inserted_at: string
  updated_at: string
}

export const runsApi = {
  list: (params?: { status?: string; source_type?: string; limit?: number }) => {
    const query = new URLSearchParams()
    if (params?.status) query.set('status', params.status)
    if (params?.source_type) query.set('source_type', params.source_type)
    if (params?.limit) query.set('limit', String(params.limit))
    const qs = query.toString()
    return request<{ runs: Run[] }>(`/api/v1/runs${qs ? `?${qs}` : ''}`)
  },

  get: (id: string) =>
    request<{ run: Run; context?: Record<string, unknown> }>(`/api/v1/runs/${id}`),

  create: (params: {
    objective: string
    source_type?: string
    mode?: string
    title?: string
    workspace_path?: string
    goal_id?: string
    autonomy_level?: number
    metadata?: Record<string, unknown>
  }) =>
    request<{ run_id: string; status: string }>('/api/v1/runs', {
      method: 'POST',
      body: JSON.stringify(params),
    }),

  cancel: (id: string) =>
    request<{ status: string }>(`/api/v1/runs/${id}/cancel`, { method: 'POST' }),

  output: (id: string) =>
    request<{ run_id: string; output: string; output_path?: string; output_summary?: string }>(`/api/v1/runs/${id}/output`),

  steps: (id: string, params?: { phase?: string; kind?: string; status?: string }) => {
    const query = new URLSearchParams()
    if (params?.phase) query.set('phase', params.phase)
    if (params?.kind) query.set('kind', params.kind)
    if (params?.status) query.set('status', params.status)
    const qs = query.toString()
    return request<{ run_id: string; steps: RunStep[] }>(`/api/v1/runs/${id}/steps${qs ? `?${qs}` : ''}`)
  },

  evidence: (id: string) =>
    request<{ run_id: string; evidence: EvidenceItem[] }>(`/api/v1/runs/${id}/evidence`),

  verification: (id: string) =>
    request<{ run_id: string; verification: Verification | null }>(`/api/v1/runs/${id}/verification`),

  messages: (id: string) =>
    request<{ run_id: string; messages: unknown[] }>(`/api/v1/runs/${id}/messages`),

  stats: () =>
    request<{ total_runs: number; by_status: Record<string, number>; by_mode: Record<string, number>; recent_runs: Run[] }>('/api/v1/runs/stats'),
}
