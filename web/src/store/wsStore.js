import { create } from 'zustand'
import { WS_URL } from '../api/client'
import { logger } from '../lib/logger'

const HEARTBEAT_MS = parseInt(import.meta.env.VITE_WS_HEARTBEAT_MS || '30000', 10)
const RECONNECT_BASE_MS = parseInt(import.meta.env.VITE_WS_RECONNECT_BASE_MS || '1000', 10)
const RECONNECT_MAX_MS = parseInt(import.meta.env.VITE_WS_RECONNECT_MAX_MS || '30000', 10)

export const useWsStore = create((set, get) => ({
  ws: null,
  connected: false,
  activeProvider: null,
  listeners: [],
  heartbeatInterval: null,
  reconnectionCount: 0,

  connect() {
    if (get().ws) return
    const ws = new WebSocket(WS_URL)

    ws.onopen = () => {
      set({ connected: true, reconnectionCount: 0 })
      // Start heartbeat: send ping every HEARTBEAT_MS to keep connection alive
      const interval = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'ping' }))
        } else {
          clearInterval(interval)
        }
      }, HEARTBEAT_MS)
      set({ heartbeatInterval: interval })
      // Notify listeners of reconnection so they can refetch session data
      get().listeners.forEach((fn) => fn({ type: 'ws_reconnected' }))
    }

    ws.onclose = () => {
      const interval = get().heartbeatInterval
      if (interval) clearInterval(interval)
      const nextReconnectCount = get().reconnectionCount + 1
      set({ connected: false, ws: null, heartbeatInterval: null, reconnectionCount: nextReconnectCount })
      // Notify listeners so they can reset streaming state
      get().listeners.forEach((fn) => fn({ type: 'ws_disconnected' }))
      setTimeout(() => get().connect(), Math.min(RECONNECT_BASE_MS * Math.pow(2, nextReconnectCount - 1), RECONNECT_MAX_MS))
    }

    ws.onmessage = (e) => {
      let msg
      try {
        msg = JSON.parse(e.data)
      } catch {
        logger.warn('WebSocket: ignoring non-JSON message', e.data)
        return
      }
      // Ignore pong responses
      if (msg.type === 'pong') return

      if (msg.type === 'event' && msg.event === 'provider_selected') {
        set({ activeProvider: msg.data.provider_name })
      }
      get().listeners.forEach((fn) => fn(msg))
    }

    set({ ws })
  },

  send(payload) {
    const { ws } = get()
    if (ws?.readyState !== WebSocket.OPEN) return false
    ws.send(JSON.stringify(payload))
    return true
  },

  subscribe(fn) {
    // Prevent duplicate subscriptions of the same function reference
    if (get().listeners.includes(fn)) {
      return () => {} // Already subscribed, no-op unsubscribe
    }
    set((s) => ({ listeners: [...s.listeners, fn] }))
    return () => set((s) => ({ listeners: s.listeners.filter((l) => l !== fn) }))
  },
}))
