import { useState, useEffect } from 'react'
import { useWsStore } from '../store/wsStore'

/**
 * Subscribe to real-time run events via WebSocket.
 * Returns { steps, subscribe, unsubscribe }.
 *
 * Steps are accumulated tool_start/tool_result events keyed by tool_use_id.
 */
export function useRunEvents(runId) {
  const [eventState, setEventState] = useState(() => ({ runId: null, stepsById: new Map() }))
  const send = useWsStore((s) => s.send)
  const subscribe = useWsStore((s) => s.subscribe)

  useEffect(() => {
    if (!runId) return

    // Subscribe to run events via WebSocket
    send({ type: 'subscribe_run', run_id: runId })

    const unsub = subscribe((msg) => {
      if (msg.type === 'event' && msg.event === 'run_event' && msg.data?.run_id === runId) {
        const data = msg.data
        const id = data.tool_use_id

        if (!id) return

        if (data.status === 'started') {
          setEventState((prev) => {
            const next = new Map(prev.runId === runId ? prev.stepsById : [])
            next.set(id, {
              id,
              tool_name: data.tool_name,
              status: 'running',
              started_at: new Date().toISOString(),
            })
            return { runId, stepsById: next }
          })
        } else if (data.status === 'success' || data.status === 'error') {
          setEventState((prev) => {
            const next = new Map(prev.runId === runId ? prev.stepsById : [])
            const existing = next.get(id)
            next.set(id, {
              ...(existing || { id, tool_name: data.tool_name || 'unknown' }),
              status: data.status,
              output: data.output || data.error || '',
              completed_at: new Date().toISOString(),
            })
            return { runId, stepsById: next }
          })
        } else if (data.status === 'complete' && data.turn_number != null) {
          // Turn complete — no action needed for step tracking
        }
      }
    })

    return () => {
      send({ type: 'unsubscribe_run', run_id: runId })
      unsub()
    }
  }, [runId, send, subscribe])

  const steps = eventState.runId === runId ? Array.from(eventState.stepsById.values()) : []

  return {
    steps,
    runningCount: steps.filter((s) => s.status === 'running').length,
    completedCount: steps.filter((s) => s.status === 'success').length,
    failedCount: steps.filter((s) => s.status === 'error').length,
  }
}
