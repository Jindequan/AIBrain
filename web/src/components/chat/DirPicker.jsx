import { useState, useEffect, useRef } from 'react'
import { FolderOpen, Folder, ChevronRight, ChevronUp, X } from 'lucide-react'
import { fsApi } from '../../api/filesystem.api'
import { logger } from '../../lib/logger'

export function DirPicker({ value, onChange, disabled, variant = 'default' }) {
  const [open, setOpen] = useState(false)
  const [path, setPath] = useState(null)
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(false)
  const ref = useRef(null)

  async function load(p) {
    setLoading(true)
    try {
      const res = await fsApi.list(p)
      setData(res)
      setPath(res.path)
    } catch (e) {
      logger.warn('DirPicker: failed to list directory', e.message)
    }
    setLoading(false)
  }

  function open_picker() {
    if (disabled) return
    setOpen(true)
    load(value || null)
  }

  function confirm() {
    if (!path) return
    onChange(path)
    setOpen(false)
  }

  function dismiss() {
    onChange(null)
    setOpen(false)
  }

  // Close on outside click
  useEffect(() => {
    if (!open) return
    function handle(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handle)
    return () => document.removeEventListener('mousedown', handle)
  }, [open])

  const displayPath = value
    ? value.split('/').filter(Boolean).slice(-2).join('/') || value
    : null

  const compact = variant === 'compact'

  return (
    <div className="relative flex items-center gap-0" ref={ref}>
      {/* Trigger */}
      <button
        type="button"
        onClick={open_picker}
        disabled={disabled}
        className={compact
          ? `flex min-w-0 items-center gap-1.5 rounded-lg px-2 py-1 text-sm transition-colors ${
              disabled ? 'cursor-default text-[#7b7f86]' : 'hover:bg-black/[0.04] cursor-pointer ' + (displayPath ? 'text-[#5f6368]' : 'text-[#7b7f86]')
            }`
          : `w-full flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs border transition-all ${
              disabled
                ? 'bg-gray-50 border-card-border text-text-muted cursor-default'
                : 'bg-gray-50 border-card-border hover:border-accent/50 cursor-pointer'
            }`
        }
      >
        <FolderOpen className={compact ? 'w-4 h-4 shrink-0' : 'w-3.5 h-3.5 text-text-muted shrink-0'} />
        {displayPath ? (
          <span className={compact ? 'min-w-0 max-w-[150px] truncate text-left' : 'flex-1 text-left truncate text-text-secondary'}>{displayPath}</span>
        ) : (
          <span className={compact ? 'min-w-0 max-w-[150px] truncate text-left' : 'flex-1 text-left text-text-muted'}>
            {disabled ? '' : ''}
          </span>
        )}
        {compact ? <ChevronRight className="w-3.5 h-3.5 rotate-90 shrink-0" /> : null}
        {disabled && !compact && <span className="text-[10px] text-text-muted border border-card-border rounded px-1 py-0.5">locked</span>}
      </button>

      {/* Clear — separate in all modes so it doesn't open the picker */}
      {displayPath && !disabled && (
        <button
          type="button"
          onClick={dismiss}
          className="p-0.5 rounded hover:bg-black/[0.08] text-[#7b7f86] hover:text-[#5f6368] transition-colors shrink-0"
        >
          <X className="w-3 h-3" />
        </button>
      )}

      {/* Dropdown */}
      {open && (
        <div className="absolute bottom-full mb-1.5 left-0 z-50 bg-white dark:bg-gray-900 border border-card-border rounded-2xl shadow-card-md overflow-hidden min-w-[320px] max-w-[480px]">
          {/* Header */}
          <div className="flex items-center gap-1 px-3 py-2 border-b border-card-border bg-gray-50 dark:bg-gray-800">
            {data?.parent !== undefined && (
              <button
                onClick={() => load(data.parent)}
                disabled={!data.parent}
                className="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 disabled:opacity-30 disabled:cursor-default transition-colors"
              >
                <ChevronUp className="w-3.5 h-3.5 text-text-muted" />
              </button>
            )}
            <span className="text-xs text-text-secondary font-mono truncate flex-1" title={data?.path}>
              {data?.path || '…'}
            </span>
            <button
              onClick={dismiss}
              className="flex items-center gap-1 px-2 py-1 rounded-lg text-[11px] font-medium transition-colors shrink-0 text-text-muted hover:bg-gray-200 dark:hover:bg-gray-700"
            >
              <X className="w-3 h-3" /> Clear directory
            </button>
            <button
              onClick={confirm}
              disabled={!path}
              className="flex items-center gap-1 px-2 py-1 rounded-lg bg-accent text-white text-[11px] font-medium hover:bg-accent/90 transition-colors shrink-0 disabled:opacity-30 disabled:cursor-default"
            >
              Use directory
            </button>
          </div>

          {/* Directory list */}
          <div className="max-h-64 overflow-y-auto">
            {loading ? (
              <div className="px-4 py-6 text-center text-xs text-text-muted">Loading…</div>
            ) : data?.dirs?.length === 0 ? (
              <div className="px-4 py-6 text-center text-xs text-text-muted">No subdirectories</div>
            ) : (
              data?.dirs?.map((d) => (
                <button
                  key={d.path}
                  onClick={() => load(d.path)}
                  className="w-full flex items-center gap-2.5 px-3 py-2 text-xs text-text-primary hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors text-left"
                >
                  <Folder className="w-3.5 h-3.5 text-accent-gold shrink-0" />
                  <span className="truncate flex-1">{d.name}</span>
                  <ChevronRight className="w-3 h-3 text-text-muted shrink-0" />
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  )
}
