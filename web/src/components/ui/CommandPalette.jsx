import { useState, useEffect, useRef, useMemo, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { Search, Command } from 'lucide-react'
import { cn } from '../../lib/utils'
import { searchApi } from '../../api/search.api'

const COMMANDS = [
  { id: '/', label: 'Today', category: 'Overview' },
  { id: '/chat', label: 'Chat', category: 'Overview' },
  { id: '/runs', label: 'Runs', category: 'Overview' },
  { id: '/approvals', label: 'Approvals', category: 'Overview' },
  { id: '/memory', label: 'Memory', category: 'Memory' },
  { id: '/artifacts', label: 'Artifacts', category: 'Workspace' },
  { id: '/goals', label: 'Goals', category: 'Workspace' },
  { id: '/tasks', label: 'Tasks', category: 'Workspace' },
  { id: '/scheduler', label: 'Scheduler', category: 'Workspace' },
  { id: '/automation-rules', label: 'Auto Rules', category: 'Workspace' },
  { id: '/channels', label: 'Channels', category: 'Integrations' },
  { id: '/providers', label: 'Providers', category: 'Integrations' },
  { id: '/voice', label: 'Voice', category: 'Integrations' },
  { id: '/security', label: 'Security', category: 'System' },
  { id: '/skills', label: 'Skills', category: 'System' },
  { id: '/plugins', label: 'Plugins', category: 'System' },
  { id: '/fs', label: 'File Browser', category: 'System' },
  { id: '/settings', label: 'Settings', category: 'System' },
]

const TYPE_LABELS = {
  session: 'Sessions',
  goal: 'Goals',
  task: 'Tasks',
  artifact: 'Artifacts',
}

const isMac = typeof navigator !== 'undefined' && navigator.platform?.startsWith('Mac')
function getShortcutHint() { return isMac ? '⌘K' : 'Ctrl+K' }

export function CommandPalette() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [animating, setAnimating] = useState(false)
  const [searchResults, setSearchResults] = useState([])
  const [searchLoading, setSearchLoading] = useState(false)

  const inputRef = useRef(null)
  const listRef = useRef(null)
  const overlayRef = useRef(null)
  const navigate = useNavigate()

  /* ---------- global search ---------- */
  useEffect(() => {
    const q = (query || '').trim()
    if (!q) return

    let cancelled = false
    const timer = setTimeout(async () => {
      try {
        const data = await searchApi.globalSearch(q)
        if (!cancelled) {
          setSearchResults(data.results || [])
        }
      } catch (err) {
        console.error('Global search failed:', err)
        if (!cancelled) {
          setSearchResults([])
        }
      } finally {
        if (!cancelled) {
          setSearchLoading(false)
        }
      }
    }, 300)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query])

  /* ---------- filtered commands ---------- */
  const filteredCommands = useMemo(() => {
    if (!query.trim()) return COMMANDS
    const q = query.toLowerCase()
    return COMMANDS.filter(
      (cmd) =>
        cmd.label.toLowerCase().includes(q) ||
        cmd.category.toLowerCase().includes(q) ||
        cmd.id.toLowerCase().includes(q),
    )
  }, [query])

  /* ---------- unified visual items ---------- */
  const items = useMemo(() => {
    const out = []
    const q = (query || '').trim()

    /* 1) Search results section */
    if (q) {
      if (searchLoading) {
        out.push({ kind: 'section-header', label: 'Searching', meta: 'loading' })
      } else if (searchResults.length === 0) {
        out.push({ kind: 'section-header', label: 'No results', meta: 'empty' })
      } else {
        for (const type of ['session', 'goal', 'task', 'artifact']) {
          const group = searchResults.filter((r) => r.type === type)
          if (group.length === 0) continue
          out.push({ kind: 'section-header', label: TYPE_LABELS[type] })
          for (const r of group) {
            out.push({ kind: 'search-result', ...r })
          }
        }
      }
    }

    /* 2) Pages section */
    if (filteredCommands.length > 0) {
      out.push({ kind: 'section-header', label: 'Pages' })
      for (const cmd of filteredCommands) {
        out.push({ kind: 'page', ...cmd })
      }
    }
    return out
  }, [query, searchLoading, searchResults, filteredCommands])

  /* ---------- open / close helpers ---------- */
  const openPalette = useCallback(() => {
    setQuery('')
    setSelectedIndex(0)
    setSearchResults([])
    setSearchLoading(false)
    setOpen(true)
    requestAnimationFrame(() => setAnimating(true))
  }, [])

  const closePalette = useCallback(() => {
    setAnimating(false)
    setTimeout(() => setOpen(false), 150)
  }, [])

  /* Focus on open */
  useEffect(() => {
    if (!open) return
    const id = setTimeout(() => inputRef.current?.focus(), 100)
    return () => clearTimeout(id)
  }, [open])

  /* ---------- keyboard shortcut ---------- */
  useEffect(() => {
    const handleKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        open ? closePalette() : openPalette()
      }
      if (e.key === 'Escape' && open) {
        e.preventDefault()
        closePalette()
      }
    }
    const handleCustomOpen = () => openPalette()
    document.addEventListener('keydown', handleKey)
    window.addEventListener('command-palette:open', handleCustomOpen)
    return () => {
      document.removeEventListener('keydown', handleKey)
      window.removeEventListener('command-palette:open', handleCustomOpen)
    }
  }, [open, openPalette, closePalette])

  /* ---------- get selectable item count ---------- */
  const selectableCount = useMemo(() => items.filter((it) => it.kind !== 'section-header').length, [items])
  const activeSelectedIndex = Math.min(selectedIndex, Math.max(selectableCount - 1, 0))

  /* ---------- keyboard navigation ---------- */
  const handleKeyDown = useCallback(
    (e) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        setSelectedIndex((prev) => (prev + 1) % Math.max(selectableCount, 1))
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        setSelectedIndex((prev) => (prev - 1 + selectableCount) % Math.max(selectableCount, 1))
      } else if (e.key === 'Enter') {
        let n = -1
        for (const it of items) {
          if (it.kind !== 'section-header') n++
          if (n === activeSelectedIndex) {
            e.preventDefault()
            if (it.kind === 'search-result' || it.kind === 'page') {
              navigate(it.url || it.id)
            }
            closePalette()
            return
          }
        }
      }
    },
    [items, activeSelectedIndex, selectableCount, navigate, closePalette],
  )

  /* ---------- click handler ---------- */
  const handleItemClick = useCallback(
    (item) => {
      if (item.kind === 'search-result' || item.kind === 'page') {
        navigate(item.url || item.id)
      }
      closePalette()
    },
    [navigate, closePalette],
  )

  /* ---------- overlay click to close ---------- */
  const handleOverlayClick = useCallback(
    (e) => {
      if (e.target === overlayRef.current) closePalette()
    },
    [closePalette],
  )

  /* ---------- scroll active into view ---------- */
  useEffect(() => {
    if (!open || !listRef.current) return
    const active = listRef.current.querySelector('[data-selected="true"]')
    active?.scrollIntoView({ block: 'nearest' })
  }, [activeSelectedIndex, open])

  /* ---------- nothing when closed ---------- */
  if (!open) return null

  /* Count selectable items to know which item has index N */
  let selectableIdx = -1

  return (
    <div
      ref={overlayRef}
      onClick={handleOverlayClick}
      className={cn(
        'fixed inset-0 z-[100] flex items-start justify-center pt-[15vh]',
        'bg-black/50 backdrop-blur-sm',
        'transition-opacity duration-150 ease-out',
        animating ? 'opacity-100' : 'opacity-0',
      )}
    >
      <div
        className={cn(
          'w-full max-w-xl bg-white rounded-2xl shadow-2xl border border-card-border',
          'overflow-hidden flex flex-col',
          'transition-all duration-150 ease-out',
          animating ? 'scale-100 opacity-100' : 'scale-95 opacity-0',
        )}
      >
        {/* ---- Search input ---- */}
        <div className="flex items-center gap-3 px-4 h-14 border-b border-border-light shrink-0">
          <Search className="w-5 h-5 text-text-muted shrink-0" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => {
              const next = e.target.value
              const hasQuery = next.trim().length > 0
              setQuery(next)
              setSelectedIndex(0)
              setSearchResults([])
              setSearchLoading(hasQuery)
            }}
            onKeyDown={handleKeyDown}
            placeholder="Search sessions, goals, tasks..."
            className="flex-1 bg-transparent text-sm text-text-primary placeholder:text-text-muted outline-none border-none"
          />
          <kbd className="hidden sm:inline-flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-text-muted bg-gray-50 rounded-lg border border-border-light shrink-0">
            <Command className="w-3 h-3" />
            {getShortcutHint().replace('⌘', '')}
          </kbd>
        </div>

        {/* ---- Results ---- */}
        <div ref={listRef} className="overflow-y-auto max-h-[min(60vh,400px)] p-2">
          {items.length === 0 ? (
            <div className="px-3 py-8 text-center text-sm text-text-muted">
              Type to search sessions, goals, tasks...
            </div>
          ) : (
            items.map((item, i) => {
              if (item.kind === 'section-header') {
                const isSearching = item.label === 'Searching' || item.label === 'No results'
                return (
                  <div key={`h-${i}`} className="block px-3 pt-2 pb-1 text-[11px] font-semibold uppercase tracking-wider text-text-muted flex items-center gap-2">
                    <span>{item.label}</span>
                    {isSearching && searchLoading && (
                      <span className="inline-block w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin" />
                    )}
                    {item.label === 'No results' && !searchLoading && (
                      <span className="text-text-muted/50 font-normal normal-case text-[10px]">try a different query</span>
                    )}
                  </div>
                )
              }

              selectableIdx++
              const isSelected = selectableIdx === activeSelectedIndex

              if (item.kind === 'search-result') {
                const typeColor = {
                  session: 'bg-blue-100 text-blue-700',
                  goal: 'bg-purple-100 text-purple-700',
                  task: 'bg-amber-100 text-amber-700',
                  artifact: 'bg-green-100 text-green-700',
                }
                return (
                  <button
                    key={`r-${item.type}-${item.id}`}
                    data-selected={isSelected}
                    onClick={() => handleItemClick(item)}
                    onMouseEnter={() => setSelectedIndex(selectableIdx)}
                    className={cn(
                      'w-full flex flex-col gap-0.5 px-3 py-2 rounded-xl text-left transition-colors duration-100',
                      isSelected ? 'bg-accent text-white' : 'text-text-primary hover:bg-gray-50',
                    )}
                  >
                    <div className="flex items-center gap-2">
                      <span className={cn(
                        'text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded',
                        isSelected ? 'bg-white/20 text-white' : typeColor[item.type] || 'bg-gray-100 text-text-muted'
                      )}>
                        {item.type}
                      </span>
                      {item.status && (
                        <span className={cn('text-[10px]', isSelected ? 'text-white/70' : 'text-text-muted')}>
                          {item.status}
                        </span>
                      )}
                    </div>
                    <span className={cn('text-sm font-medium', isSelected ? 'text-white' : 'text-text-primary')}>
                      {item.title}
                    </span>
                    {item.subtitle && (
                      <p className={cn('text-xs leading-relaxed line-clamp-1', isSelected ? 'text-white/80' : 'text-text-secondary')}>
                        {item.subtitle}
                      </p>
                    )}
                  </button>
                )
              }

              if (item.kind === 'page') {
                return (
                  <button
                    key={item.id}
                    data-selected={isSelected}
                    onClick={() => handleItemClick(item)}
                    onMouseEnter={() => setSelectedIndex(selectableIdx)}
                    className={cn(
                      'w-full flex items-center justify-between px-3 py-2.5 rounded-xl text-left transition-colors duration-100',
                      isSelected ? 'bg-accent text-white' : 'text-text-primary hover:bg-gray-50',
                    )}
                  >
                    <span className="text-sm font-medium">{item.label}</span>
                    <span className={cn('text-[11px] font-mono', isSelected ? 'text-white/70' : 'text-text-muted')}>
                      {item.id}
                    </span>
                  </button>
                )
              }

              return null
            })
          )}
        </div>

        {/* ---- Footer ---- */}
        <div className="flex items-center gap-4 px-4 py-2.5 border-t border-border-light bg-gray-50/50 shrink-0">
          <div className="flex items-center gap-1.5 text-[11px] text-text-muted">
            <kbd className="px-1.5 py-0.5 bg-white rounded border border-border-light text-[10px] font-mono">&uarr;</kbd>
            <kbd className="px-1.5 py-0.5 bg-white rounded border border-border-light text-[10px] font-mono">&darr;</kbd>
            <span>navigate</span>
          </div>
          <div className="flex items-center gap-1.5 text-[11px] text-text-muted">
            <kbd className="px-1.5 py-0.5 bg-white rounded border border-border-light text-[10px] font-mono">&crarr;</kbd>
            <span>open</span>
          </div>
          <div className="flex items-center gap-1.5 text-[11px] text-text-muted">
            <kbd className="px-1.5 py-0.5 bg-white rounded border border-border-light text-[10px] font-mono">esc</kbd>
            <span>close</span>
          </div>
        </div>
      </div>
    </div>
  )
}
