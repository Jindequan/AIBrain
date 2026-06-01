import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useChatStore } from '../store/chatStore'
import { useToastStore } from '../store/toastStore'

/**
 * Event handler map: event name → (data, msg, context) => void
 *
 * context = { store, toast, queryClient, sessionId }
 */
const EVENT_HANDLERS = {
  text_delta(data, _msg, { store }) {
    store.appendTextDelta(data.text || '')
  },
  thinking_start(data, _msg, { store }) {
    store.startThinkingBlock(data.thinking_index)
  },
  thinking_delta(data, _msg, { store }) {
    store.appendThinkingDelta(data.thinking_index, data.text || '')
  },
  thinking_end(data, _msg, { store }) {
    store.endThinkingBlock(data.thinking_index)
  },
  tool_use_start_sse(data, _msg, { store }) {
    store.addToolUse(data.tool_name, data.tool_use_id, data.input || {})
  },
  tool_input_delta(data, _msg, { store }) {
    store.appendToolInputDelta(data.tool_use_index, data.chunk || '')
  },
  tool_start(data, _msg, { store }) {
    store.addToolUse(data.tool_name, data.tool_use_id, data.input)
  },
  tool_result(data, _msg, { store }) {
    store.setToolResult(data.tool_use_id, data.output, data.status)
  },
  tool_timeout(data, _msg, { store }) {
    store.setToolResult(data.tool_use_id, data.message || 'Tool timed out', 'error')
  },
  tool_crashed(data, _msg, { store }) {
    store.setToolResult(data.tool_use_id, data.message || data.reason || 'Tool crashed', 'error')
  },
  tool_exited(data, _msg, { store }) {
    store.setToolResult(data.tool_use_id, data.message || data.reason || 'Tool exited', 'error')
  },
  sandbox_feedback(data, _msg, { store }) {
    store.setToolResult(data.tool_use_id, `Sandbox blocked: ${data.operation}`, 'error')
  },
  provider_connecting(data, _msg, { store }) {
    store.setStatus({ text: `Connecting to ${data.provider_name}...`, type: 'connecting' })
  },
  provider_selected(data, _msg, { store }) {
    store.setStatus({ text: `Using ${data.provider_name}`, type: 'info' })
  },
  provider_failed(data, _msg, { store, toast }) {
    if (data.retry_at != null && data.provider_name) {
      store.setStatus({ text: `Retrying ${data.provider_name}...`, type: 'info' })
    } else {
      const detail = data.message || data.error || data.reason || 'AI service is temporarily unavailable. Please try again later.'
      toast.addToast({ title: 'Provider failed', message: detail, variant: 'error' })
    }
  },
  context_truncated(data, _msg, { toast }) {
    toast.addToast({ title: 'Context limit reached', message: `${data.dropped_count} older messages removed to fit window`, variant: 'warning' })
  },
  query_failed(data, _msg, { store, toast }) {
    const errDetail = data?.message || data?.error || data?.reason || 'Query failed'
    toast.addToast({ title: 'Query failed', message: errDetail, variant: 'error' })
    store.finishStreaming(errDetail)
  },
  query_complete(data, msg, { store, queryClient }) {
    store.appendAssistantTextIfEmpty(data?.response || data?.text || '')
    store.finishStreaming()
    // Don't invalidate the active session — messages are already up-to-date from streaming.
    // The sessions list still needs invalidation for title / message-count display.
    queryClient.invalidateQueries({ queryKey: ['sessions'] })
  },
  session_title_updated(data, _msg, { queryClient }) {
    if (data?.title) queryClient.invalidateQueries({ queryKey: ['sessions'] })
  },
}

const NOTIFICATION_TITLES = {
  task_completed: 'Task completed',
  task_failed: 'Task failed',
  run_completed: 'Run complete',
  scheduler_fired: 'Scheduler triggered',
  interaction_needed: 'Approval Required',
  interaction_escalated: 'Approval Escalated',
}

function approvalPayload(msg) {
  const data = msg.data || {}
  const schema = data.schema || {}
  const context = data.context || {}

  return {
    ...data,
    session_id: msg.session_id || data.session_id || context.session_id,
    run_id: msg.run_id || data.run_id || context.run_id,
    status: msg.status || data.status || 'waiting_approval',
    reason: msg.reason || data.reason || schema.reason || schema.title || 'This request needs your approval before it can continue.',
    title: msg.title || data.title || schema.title,
    approval_id: msg.approval_id || data.approval_id || data.interaction_id || msg.interaction_id,
    interaction_id: msg.interaction_id || data.interaction_id || data.approval_id || msg.approval_id,
    tool_name: msg.tool_name || data.tool_name || schema.tool_name,
  }
}

function isCurrentApproval(payload, store) {
  return !payload.session_id || !store.activeSessionId || payload.session_id === store.activeSessionId || store.streaming
}

export function useChatWebSocket({ subscribe }) {
  const queryClient = useQueryClient()

  useEffect(() => {
    const unsub = subscribe((msg) => {
      try {
        const messageSessionId = msg.session_id || msg.data?.session_id
        const store = useChatStore.getState()
        const toast = useToastStore.getState()
        const isActiveChatMessage = !messageSessionId || !store.activeSessionId || messageSessionId === store.activeSessionId
        const ctx = { store, toast, queryClient, sessionId: messageSessionId }

      if (msg.type === 'event') {
        if (!isActiveChatMessage) return
        const handler = EVENT_HANDLERS[msg.event]
        if (handler) handler(msg.data, msg, ctx)

      } else if (msg.type === 'response') {
        if (!isActiveChatMessage) {
          if (messageSessionId) queryClient.invalidateQueries({ queryKey: ['session', messageSessionId] })
          queryClient.invalidateQueries({ queryKey: ['sessions'] })
          return
        }
        store.appendAssistantTextIfEmpty(msg.text || msg.response || '')
        store.finishStreaming()
        // Don't invalidate the active session — messages are already up-to-date from streaming.
        // The sessions list still needs invalidation for title / message-count display.
        queryClient.invalidateQueries({ queryKey: ['sessions'] })

      } else if (msg.type === 'notification') {
        const title = NOTIFICATION_TITLES[msg.event] || 'Notification'
        const variant = msg.event === 'interaction_needed' || msg.event === 'interaction_escalated' ? 'warning' : 'info'
        const approval = approvalPayload(msg)
        const detail = msg.data?.name || approval.title || approval.reason || ''

        // Approval/escale events use the global InteractionModal — skip toast and system notification
        const isInteractionEvent = msg.event === 'interaction_needed' || msg.event === 'interaction_escalated'
        if (!isInteractionEvent) {
          toast.addToast({ title, message: detail, variant })
          if (window.electronAPI?.notify) {
            window.electronAPI.notify(title, detail || msg.data?.monitor_id || '')
          }
        }

        if (msg.event === 'interaction_needed') {
          window.dispatchEvent(new CustomEvent('interaction-needed', { detail: { interaction_id: approval.interaction_id } }))
        } else if (msg.event === 'interaction_resolved') {
          if (isCurrentApproval(approvalPayload(msg), store)) {
            store.resumeStreamingAfterApproval()
          }
          window.dispatchEvent(new CustomEvent('interaction-resolved', { detail: { interaction_id: msg.data?.interaction_id } }))
        } else if (msg.event === 'interaction_escalated') {
          window.dispatchEvent(new CustomEvent('interaction-escalated', { detail: { interaction_id: msg.data?.interaction_id } }))
        }

      } else if (msg.type === 'error') {
        if (!isActiveChatMessage) return
        toast.addToast({ title: 'Query failed', message: msg.error || 'Query failed', variant: 'error' })
        store.finishStreaming(msg.error || 'Query failed')

      } else if (msg.type === 'ws_disconnected') {
        toast.addToast({ title: 'Connection lost', message: 'WebSocket connection lost. Reconnecting...', variant: 'warning' })
        if (store.streaming) store.interruptStreaming()

      } else if (msg.type === 'ws_reconnected') {
        const sessionId = store.activeSessionId
        if (sessionId) {
          queryClient.invalidateQueries({ queryKey: ['session', sessionId] })
          queryClient.invalidateQueries({ queryKey: ['sessions'] })
        }
      }
      } catch (e) {
        console.error('WebSocket message handler error:', e)
      }
    })
    return unsub
  }, [subscribe, queryClient])
}
