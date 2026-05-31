/**
 * Unified time formatting — all timestamps displayed in user's local timezone.
 * Backend sends UTC ISO 8601 strings; new Date() parses them correctly.
 */

/**
 * Relative time: "just now", "5m ago", "2h ago", "3d ago", "May 21"
 */
export function formatRelative(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d)) return ''
  const diff = Date.now() - d.getTime()
  if (diff < 60_000) return 'just now'
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`
  if (diff < 604_800_000) return `${Math.floor(diff / 86_400_000)}d ago`
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

/**
 * Absolute local time: "5/21/2026, 3:45:02 PM"
 */
export function formatAbsolute(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d)) return ''
  return d.toLocaleString()
}

/**
 * Short time for message bubbles: "3:45 PM" today, "May 21" otherwise
 */
export function formatMessageTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d)) return ''
  const now = new Date()
  const sameDay = d.toDateString() === now.toDateString()
  if (sameDay) {
    return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
  }
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })
}
