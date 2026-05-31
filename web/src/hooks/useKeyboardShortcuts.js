import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

const isMac = typeof window !== 'undefined' && window.electronAPI?.platform === 'darwin'
const mod = isMac ? 'metaKey' : 'ctrlKey'

export function useKeyboardShortcuts() {
  const navigate = useNavigate()

  useEffect(() => {
    const handler = (e) => {
      // Don't trigger shortcuts when typing in inputs
      const tag = e.target.tagName
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return

      // Cmd/Ctrl + K — Command palette (handled by CommandPalette component)
      // Cmd/Ctrl + , — Settings
      if (e[mod] && e.key === ',') {
        e.preventDefault()
        navigate('/settings')
      }
      // Cmd/Ctrl + N — New chat
      if (e[mod] && e.key === 'n') {
        e.preventDefault()
        navigate('/chat')
      }
      // Cmd/Ctrl + 1-9 — Quick nav
      if (e[mod] && e.key >= '1' && e.key <= '9') {
        e.preventDefault()
        const routes = ['/', '/chat', '/memory', '/goals', '/tasks', '/channels', '/providers', '/settings', '/users']
        const idx = parseInt(e.key) - 1
        if (routes[idx]) navigate(routes[idx])
      }
    }

    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [navigate])
}
