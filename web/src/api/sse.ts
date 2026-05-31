import type { WsQueryRequest } from '../models/types'
import { buildApiUrl } from './client'

export interface SseCallbacks {
  onStart?: () => void
  onToolResult?: (data: any) => void
  onTextDelta?: (text: string) => void
  onComplete?: (response: string) => void
  onSuspended?: (data: any) => void
  onError?: (error: string) => void
  onWarning?: (warning: string) => void

}

/**
 * SSE client — sends query via POST /api/v1/query/stream
 * Fallback when WebSocket is unavailable.
 *
 * Note: backend SSE endpoint uses standard SSE format,
 * but since it's a POST request, EventSource API cannot be used,
 * must parse manually via fetch + ReadableStream.
 */
export function sseQuery(params: WsQueryRequest, callbacks: SseCallbacks): AbortController {
  const controller = new AbortController()

  fetch(buildApiUrl('/api/v1/query/stream'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
    signal: controller.signal,
  })
    .then(async (response) => {
      if (!response.ok) {
        let body: any = null
        try { body = await response.json() } catch { /* ignore */ }
        callbacks.onError?.(body?.error || `SSE error: ${response.status}`)
        return
      }

      const reader = response.body?.getReader()
      if (!reader) {
        callbacks.onError?.('SSE: no response body')
        return
      }

      const decoder = new TextDecoder()
      let buffer = ''
      let currentEvent = ''
      let currentData = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() || '' // keep incomplete line in buffer

        currentEvent = ''
        currentData = ''

        for (const line of lines) {
          if (line.startsWith('event: ')) {
            currentEvent = line.slice(7).trim()
          } else if (line.startsWith('data: ')) {
            currentData = line.slice(6).trim()
          } else if (line === '') {
            // Empty line — event boundary
            if (currentData) {
              handleSseEvent(currentEvent, currentData, callbacks)
            }
            currentEvent = ''
            currentData = ''
          }
        }
      }

      // Handle any remaining data
      if (currentData) {
        handleSseEvent(currentEvent, currentData, callbacks)
      }
    })
    .catch((err) => {
      if (err.name !== 'AbortError') {
        callbacks.onError?.(err.message || 'SSE connection failed')
      }
    })

  return controller
}

function handleSseEvent(event: string, rawData: string, callbacks: SseCallbacks) {
  let data: any
  try {
    data = JSON.parse(rawData)
  } catch {
    return
  }

  switch (event) {
    case 'start':
      callbacks.onStart?.()
      break
    case 'message':
      // data.type is the event type from backend (tool_result, text_delta, etc.)
      // data.data contains the event payload
      const eventType = data.type
      const payload = data.data || {}

      switch (eventType) {
        case 'tool_result':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            output: payload.output || payload.result,
            status: payload.status || 'success'
          })
          break
        case 'tool_start':
        case 'tool_use_start_sse':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            tool_name: payload.tool_name,
            input: payload.input,
            status: 'running'
          })
          break
        case 'tool_timeout':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            output: payload.message || 'Tool timed out',
            status: 'error'
          })
          break
        case 'tool_crashed':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            output: payload.message || payload.reason || 'Tool crashed',
            status: 'error'
          })
          break
        case 'tool_exited':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            output: payload.message || payload.reason || 'Tool exited',
            status: 'error'
          })
          break
        case 'sandbox_feedback':
          callbacks.onToolResult?.({
            tool_use_id: payload.tool_use_id,
            output: `Sandbox blocked: ${payload.operation}`,
            status: 'error'
          })
          break
        case 'text_delta':
          callbacks.onTextDelta?.(payload.text || '')
          break
        case 'provider_connecting':
        case 'provider_selected':
          // Provider status changes - informational, no user action needed
          break
        case 'provider_failed':
          // Only report as error if not retrying
          if (payload.retry_at == null) {
            const reason = payload.raw_error || payload.reason || 'Provider connection failed'
            callbacks.onError?.(`Provider error: ${reason}`)
          }
          break
        case 'context_truncated':
          const droppedMsg = `${payload.dropped_count || 0} older messages removed to fit context window`
          callbacks.onWarning?.(droppedMsg)
          break
        case 'query_failed':
          callbacks.onError?.(payload.reason || payload.error || 'Query failed')
          break
      }
      break
    case 'complete':
      callbacks.onComplete?.(data.response || '')
      break
    case 'suspended':
      callbacks.onSuspended?.(data)
      break
    case 'error':
      callbacks.onError?.(data.error || 'Unknown SSE error')
      break
  }
}

/**
 * Sync fallback — get response via REST POST /api/v1/query
 */
export async function syncQuery(params: WsQueryRequest): Promise<string> {
  const response = await fetch(buildApiUrl('/api/v1/query'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  })

  if (!response.ok) {
    let body: any = null
    try { body = await response.json() } catch { /* ignore */ }
    throw new Error(body?.error || `${response.status} ${response.statusText}`)
  }

  const result = await response.json()
  if (!result.success) {
    throw new Error(result.error || 'Query failed')
  }
  return result.response
}
