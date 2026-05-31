import { create } from 'zustand'

export const useNotificationStore = create((set) => ({
  notifications: [],

  addNotification(notification) {
    const entry = {
      id: notification.monitor_id || `notif-${Date.now()}`,
      name: notification.name || 'Monitor',
      result: notification.result || '',
      timestamp: notification.completed_at || new Date().toISOString(),
      read: false,
    }
    set((s) => ({
      notifications: [entry, ...s.notifications].slice(0, 50), // keep last 50
    }))

    // Auto-dismiss after 8 seconds
    setTimeout(() => {
      set((s) => ({
        notifications: s.notifications.map((n) =>
          n.id === entry.id ? { ...n, dismissed: true } : n
        ),
      }))
    }, 8000)
  },

  markAllRead() {
    set((s) => ({
      notifications: s.notifications.map((n) => ({ ...n, read: true })),
    }))
  },

  clearDismissed() {
    set((s) => ({
      notifications: s.notifications.filter((n) => !n.dismissed),
    }))
  },
}))
