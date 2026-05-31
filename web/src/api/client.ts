export const API_BASE = trimTrailingSlash(import.meta.env.VITE_API_URL || '')

interface RequestOptions extends RequestInit {
  params?: Record<string, string | number | boolean | undefined>;
}

export class ApiError extends Error {
  status: number
  body: any

  constructor(status: number, body: any) {
    const bodyMsg = body?.error || body?.message || ''
    const msg = bodyMsg || `${status} ${statusTextFor(status)}`
    super(msg)
    this.name = 'ApiError'
    this.status = status
    this.body = body
  }
}

function statusTextFor(status: number): string {
  const map: Record<number, string> = {
    400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden',
    404: 'Not Found', 422: 'Unprocessable Entity',
    500: 'Internal Server Error', 503: 'Service Unavailable',
  }
  return map[status] || `Error ${status}`
}

type ErrorHandler = (error: ApiError) => void
let globalErrorHandler: ErrorHandler | null = null

export function setGlobalErrorHandler(handler: ErrorHandler | null) {
  globalErrorHandler = handler
}

async function handleResponse(res: Response): Promise<any> {
  if (!res.ok) {
    let body: any = null
    try { body = await res.json() } catch { /* ignore */ }
    const error = new ApiError(res.status, body)
    globalErrorHandler?.(error)
    throw error
  }
  if (res.status === 204) return null
  const text = await res.text()
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch {
    return text
  }
}

async function handleTextResponse(res: Response): Promise<string> {
  if (!res.ok) {
    let body: any = null
    try { body = await res.json() } catch { /* ignore */ }
    const error = new ApiError(res.status, body)
    globalErrorHandler?.(error)
    throw error
  }
  return res.text()
}

function buildUrl(path: string, params?: Record<string, string | number | boolean | undefined>): string {
  let url = buildApiUrl(path)
  if (params) {
    const entries = Object.entries(params)
      .filter((entry): entry is [string, string | number | boolean] => entry[1] !== undefined)
      .map(([key, value]) => [key, String(value)])
    const qs = new URLSearchParams(entries).toString()
    url += `?${qs}`
  }
  return url
}

export function buildApiUrl(path: string): string {
  if (/^https?:\/\//i.test(path)) return path
  return `${API_BASE}${path.startsWith('/') ? path : `/${path}`}`
}

function trimTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '')
}

function wsBaseFromApiBase(): string {
  if (!API_BASE) return ''
  return API_BASE.replace(/^http/i, 'ws')
}

function buildWsUrl(): string {
  const explicit = trimTrailingSlash(import.meta.env.VITE_WS_URL || '')
  const base = explicit || wsBaseFromApiBase()
  return base.endsWith('/api/v1/ws') ? base : `${base}/api/v1/ws`
}

export async function request<T = any>(path: string, options: RequestOptions = {}): Promise<T> {
  const { params: _params, ...fetchOptions } = options
  const url = buildUrl(path, options.params)
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...fetchOptions.headers as Record<string, string> },
    ...fetchOptions,
  })
  return handleResponse(res)
}

export async function requestText(path: string, options: RequestOptions = {}): Promise<string> {
  const { params: _params, ...fetchOptions } = options
  const url = buildUrl(path, options.params)
  const res = await fetch(url, {
    headers: { 'Content-Type': 'application/json', ...fetchOptions.headers as Record<string, string> },
    ...fetchOptions,
  })
  return handleTextResponse(res)
}

export const WS_URL = buildWsUrl()
