import { useState, useEffect, useRef } from 'react'
import { Bell, BellRing, X } from 'lucide-react'
import { useWsStore } from '../../store/wsStore'
import { useNotificationStore } from '../../store/notificationStore'
import { cn } from '../../lib/utils'

export function NotificationBell() {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const subscribe = useWsStore((s) => s.subscribe)
  const { notifications, markAllRead, clearDismissed } = useNotificationStore()
  const addNotification = useNotificationStore((s) => s.addNotification)

  const unreadCount = notifications.filter((n) => !n.read && !n.dismissed).length
  const active = notifications.filter((n) => !n.dismissed)

  // Listen for monitor notifications via WebSocket
  useEffect(() => {
    const unsub = subscribe((msg) => {
      if (msg.type === 'monitor_notification' && msg.event === 'monitor_result') {
        addNotification(msg.data)
      }
    })
    return unsub
  }, [subscribe, addNotification])

  // Close on outside click
  useEffect(() => {
    if (!open) return
    function handle(e) {
      if (ref.current && !ref.current.contains(e.target)) {
        setOpen(false)
        clearDismissed()
      }
    }
    document.addEventListener('mousedown', handle)
    return () => document.removeEventListener('mousedown', handle)
  }, [open, clearDismissed])

  function handleToggle() {
    if (!open) markAllRead()
    setOpen(!open)
  }

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={handleToggle}
        className="relative p-1.5 rounded-md hover:bg-white/70 dark:hover:bg-white/10 text-text-muted hover:text-text-primary transition-colors"
      >
        {unreadCount > 0 ? (
          <>
            <BellRing className="w-4 h-4" />
            <span className="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-red-500 animate-pulse" />
          </>
        ) : (
          <Bell className="w-4 h-4" />
        )}
      </button>

      {open && (
        <div className="absolute right-0 top-full mt-1 w-80 bg-white rounded-xl border border-border-light shadow-lg z-50 overflow-hidden">
          <div className="px-3 py-2 border-b border-border-light flex items-center justify-between">
            <span className="text-xs font-semibold text-text-primary">Notifications</span>
            {active.length > 0 && (
              <button onClick={() => setOpen(false)}
                className="text-text-muted hover:text-text-primary p-0.5">
                <X className="w-3 h-3" />
              </button>
            )}
          </div>
          <div className="max-h-72 overflow-y-auto divide-y divide-card-border">
            {active.length === 0 && (
              <div className="px-4 py-8 text-center text-text-muted text-xs">No notifications</div>
            )}
            {active.map((n) => (
              <div key={n.id} className={cn('px-4 py-3', !n.read && 'bg-accent/5')}>
                <div className="flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-accent shrink-0" />
                  <span className="text-xs font-medium text-text-primary">{n.name}</span>
                </div>
                <p className="text-xs text-text-secondary mt-1 line-clamp-2">{n.result}</p>
                <p className="text-[10px] text-text-muted mt-1">
                  {new Date(n.timestamp).toLocaleTimeString()}
                </p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
