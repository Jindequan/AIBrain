import { useState, useEffect } from 'react'
import { cn } from '../../lib/utils'

const PLATFORM = typeof window !== 'undefined'
  ? window.electronAPI?.platform || 'unknown'
  : 'unknown'

const isMac = PLATFORM === 'darwin'
const isWindows = PLATFORM === 'win32'
const isElectron = typeof window !== 'undefined' && window.electronAPI?.isElectron

export default function TitleBar() {
  const [isMaximized, setIsMaximized] = useState(false)

  useEffect(() => {
    if (!isElectron) return

    // Check initial state
    window.electronAPI.isMaximized().then(setIsMaximized)

    // Listen for maximize/unmaximize
    window.electronAPI.onMaximizeChange(setIsMaximized)
    window.electronAPI.onMenuAction((action) => {
      if (action === 'settings') {
        window.dispatchEvent(new CustomEvent('navigate', { detail: '/settings' }))
      }
    })

    return () => {
      window.electronAPI.removeMaximizeListener()
      window.electronAPI.removeMenuActionListener()
    }
  }, [])

  // macOS: minimal invisible titlebar — traffic lights are native
  if (isMac) {
    return (
      <header
        className="h-10 shrink-0"
        style={{ WebkitAppRegion: 'drag' }}
      />
    )
  }

  // Windows: full custom titlebar with controls
  if (isWindows) {
    return (
      <header
        className="h-9 shrink-0 flex items-center bg-[#f0f0f0] border-b border-gray-200 select-none"
        style={{ WebkitAppRegion: 'drag' }}
      >
        {/* App icon + title */}
        <div className="flex items-center gap-2 px-3">
          <img src="/logo.png" alt="" className="w-4 h-4 rounded" />
          <span className="text-xs font-medium text-gray-700">AIBrain</span>
        </div>

        {/* Spacer */}
        <div className="flex-1" />

        {/* Window controls */}
        <div className="flex" style={{ WebkitAppRegion: 'no-drag' }}>
          <WindowButton onClick={() => window.electronAPI.minimize()} label="Minimize">
            <MinimizeIcon />
          </WindowButton>
          <WindowButton onClick={() => window.electronAPI.maximize()} label={isMaximized ? 'Restore' : 'Maximize'}>
            {isMaximized ? <RestoreIcon /> : <MaximizeIcon />}
          </WindowButton>
          <WindowButton onClick={() => window.electronAPI.close()} label="Close" className="hover:bg-red-500 hover:text-white">
            <CloseIcon />
          </WindowButton>
        </div>
      </header>
    )
  }

  // Linux / fallback
  return null
}

function WindowButton({ onClick, label, children, className }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        'w-11 h-9 flex items-center justify-center text-gray-500 hover:bg-gray-200 transition-colors text-sm',
        className
      )}
    >
      {children}
    </button>
  )
}

/* ── SVG Icons ─────────────────────────────── */

function MinimizeIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10">
      <rect y="4.5" width="10" height="1" fill="currentColor" />
    </svg>
  )
}

function MaximizeIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10">
      <rect x="1" y="1" width="8" height="8" rx="1" fill="none" stroke="currentColor" strokeWidth="1" />
    </svg>
  )
}

function RestoreIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10">
      <rect x="2" y="0" width="7" height="7" rx="1" fill="none" stroke="currentColor" strokeWidth="1" />
      <rect x="0" y="2" width="7" height="7" rx="1" fill="white" stroke="currentColor" strokeWidth="1" />
    </svg>
  )
}

function CloseIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10">
      <line x1="1" y1="1" x2="9" y2="9" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
      <line x1="9" y1="1" x2="1" y2="9" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  )
}
