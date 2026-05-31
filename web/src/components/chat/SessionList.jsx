import { useRef, useState, useCallback, useMemo, memo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2, Check, X, Send, MessageSquare, Search, Pencil, Gamepad2, BookOpen, Copy } from 'lucide-react'
import { useVirtualizer } from '@tanstack/react-virtual'
import ContextMenu from '../desktop/ContextMenu'
import { sessionsApi } from '../../api/sessions.api'
import { useChatStore } from '../../store/chatStore'
import { cn } from '../../lib/utils'

const iconColors = {
  telegram: 'text-accent',
  discord: 'text-indigo-500',
  feishu: 'text-blue-500',
}

function getSessionIcon(s) {
  switch (s.channel_adapter) {
    case 'telegram': return Send
    case 'discord': return Gamepad2
    case 'feishu': return BookOpen
    default: return MessageSquare
  }
}

function channelLabel(s) {
  switch (s.channel_adapter) {
    case 'telegram': return 'Telegram'
    case 'discord': return 'Discord'
    case 'feishu': return 'Feishu'
    default: return null
  }
}

function wsLabel(s) {
  if (!s.workspace_path) return null
  return s.workspace_name || s.workspace_path.split('/').pop()
}

export const SessionList = memo(function SessionList() {
  const navigate = useNavigate()
  const { activeSessionId, setActiveSession, setSessions } = useChatStore()
  const [editingId, setEditingId] = useState(null)
  const [editValue, setEditValue] = useState('')
  const [searchQuery, setSearchQuery] = useState('')
  const editInputRef = useRef(null)
  const listRef = useRef(null)
  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery({
    queryKey: ['sessions'],
    queryFn: async () => {
      const res = await sessionsApi.list()
      setSessions(res.sessions)
      return res
    },
    refetchInterval: 60000,
  })

  const allSessions = useMemo(() => data?.sessions || [], [data?.sessions])

  const visibleSessions = useMemo(() => {
    let list = allSessions
    if (searchQuery) {
      const q = searchQuery.toLowerCase()
      list = list.filter(s => (s.title || '').toLowerCase().includes(q))
    }
    return [...list].sort(
      (a, b) => new Date(b.updated_at || b.created_at) - new Date(a.updated_at || a.created_at)
    )
  }, [allSessions, searchQuery])

  const virtualizer = useVirtualizer({
    count: visibleSessions.length,
    getScrollElement: () => listRef.current,
    estimateSize: () => 52,
    overscan: 5,
  })

  const del = useMutation({
    mutationFn: (id) => sessionsApi.delete(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sessions'] }),
  })

  const rename = useMutation({
    mutationFn: async ({ id, title }) => {
      return sessionsApi.update(id, { title })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
    },
    onError: (error) => {
      console.error('Failed to rename session:', error)
      alert(`Failed to rename session: ${error.message || 'Unknown error'}`)
    }
  })

  const startEditing = useCallback((s) => {
    setEditingId(s.session_id || s.id)
    setEditValue(s.title || s.session_id || s.id)
    setTimeout(() => editInputRef.current?.focus(), 0)
  }, [])

  const commitEdit = useCallback(() => {
    if (editingId && editValue.trim()) {
      rename.mutate({ id: editingId, title: editValue.trim() })
    }
    setEditingId(null)
    setEditValue('')
  }, [editingId, editValue, rename])

  const cancelEdit = useCallback(() => {
    setEditingId(null)
    setEditValue('')
  }, [])

  const handleSelectSession = useCallback((s) => {
    const id = s.session_id || s.id
    if (id === activeSessionId) return
    setActiveSession(id)
    navigate(`/sessions/${id}`)
  }, [activeSessionId, setActiveSession, navigate])

  const handleNewSession = () => {
    setActiveSession(null)
    navigate('/chat')
  }

  return (
    <aside className="w-56 border-r border-border-light flex flex-col bg-white shrink-0">
      <div className="p-3 border-b border-card-border">
        <button onClick={handleNewSession}
          className="w-full flex items-center gap-2 px-3 py-2 rounded-xl bg-dark-primary hover:bg-dark-secondary text-white text-sm font-semibold transition-all"
        >
          <Plus className="w-4 h-4" /> New session
        </button>
      </div>

      <div className="px-2 py-1.5">
        <div className="flex items-center gap-1.5 px-2 py-1.5 rounded-lg bg-gray-50 border border-card-border text-text-muted">
          <Search className="w-3.5 h-3.5 shrink-0" />
          <input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search..."
            className="flex-1 bg-transparent text-xs text-text-primary outline-none placeholder:text-text-muted/60"
          />
        </div>
      </div>

      <div ref={listRef} className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="px-3 py-2 space-y-2">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="flex items-center gap-2 px-2 py-2.5">
                <div className="w-3.5 h-3.5 rounded bg-gray-200 animate-pulse" />
                <div className="flex-1 h-3 rounded bg-gray-200 animate-pulse" style={{ width: `${60 + Math.random() * 30}%` }} />
              </div>
            ))}
          </div>
        ) : (
        <div style={{ height: `${virtualizer.getTotalSize()}px`, width: '100%', position: 'relative' }}>
          {virtualizer.getVirtualItems().map((virtualItem) => {
            const s = visibleSessions[virtualItem.index]
            if (!s) return null

            const id = s.session_id || s.id
            const Icon = getSessionIcon(s)
            const workspace = wsLabel(s)
            const channelName = channelLabel(s)

            return (
              <ContextMenu key={id} items={[
                { label: 'Rename', icon: <Pencil className="w-3.5 h-3.5" />, onClick: () => startEditing(s) },
                { label: 'Copy ID', icon: <Copy className="w-3.5 h-3.5" />, onClick: () => {
                  if (window.electronAPI?.writeClipboard) {
                    window.electronAPI.writeClipboard(id)
                  } else {
                    navigator.clipboard.writeText(id).catch(() => {})
                  }
                }},
                { separator: true },
                { label: 'Delete', icon: <Trash2 className="w-3.5 h-3.5" />, danger: true, onClick: () => del.mutate(id) },
              ]}>
              <div
                style={{
                  position: 'absolute', top: 0, left: 0, width: '100%',
                  height: `${virtualItem.size}px`, transform: `translateY(${virtualItem.start}px)`,
                }}
                onClick={() => handleSelectSession(s)}
                className={cn(
                  'flex items-center justify-between cursor-pointer text-sm transition-all duration-200 border-b border-card-border last:border-b-0 group',
                  activeSessionId === id ? 'text-text-primary bg-accent/6 border-l-2 border-l-accent' : 'text-text-secondary hover:bg-gray-50 hover:text-text-primary border-l-2 border-l-transparent'
                )}
              >
                <div className={cn(
                  'overflow-hidden min-w-0 flex-1 flex py-1.5 px-3',
                  editingId === id ? 'items-center gap-1.5' : 'items-start gap-1.5'
                )}>
                  <Icon className={cn('w-3.5 h-3.5 shrink-0', editingId !== id && 'mt-0.5', iconColors[s.channel_adapter] || 'text-text-muted')} />
                  {editingId === id ? (
                    <div className="flex items-center gap-1 flex-1">
                      <input ref={editInputRef} value={editValue}
                        onChange={(e) => setEditValue(e.target.value)}
                        onKeyDown={(e) => { if (e.key === 'Enter') commitEdit(); if (e.key === 'Escape') cancelEdit() }}
                        className="w-full text-xs px-2 py-1 rounded-lg border border-accent bg-white outline-none"
                      />
                      <button onClick={commitEdit} className="p-1 text-accent-green-dark hover:text-accent-green shrink-0"><Check className="w-3.5 h-3.5" /></button>
                      <button onClick={cancelEdit} className="p-1 text-accent-red hover:text-red-600 shrink-0"><X className="w-3.5 h-3.5" /></button>
                    </div>
                  ) : (
                    <div className="flex flex-col min-w-0 flex-1">
                      <p className="truncate text-xs font-medium text-text-primary cursor-text hover:text-accent transition-colors"
                        onDoubleClick={() => startEditing(s)} title="Double-click to rename">
                        {s.title || id}
                      </p>
                      {(channelName || workspace) && (
                        <div className="flex items-center gap-1.5 mt-0.5">
                          {channelName && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded-md bg-gray-100 truncate max-w-[80px]">
                              {channelName}
                            </span>
                          )}
                          {workspace && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded-md bg-gray-100 text-text-muted truncate max-w-[80px]">
                              {workspace}
                            </span>
                          )}
                        </div>
                      )}
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-1 shrink-0 pr-2">
                  <button onClick={(e) => { e.stopPropagation(); startEditing(s) }}
                    className="p-1 rounded-lg opacity-0 group-hover:opacity-100 hover:text-blue-500 text-text-muted transition-all" title="Rename">
                    <Pencil className="w-3 h-3" />
                  </button>
                  <button onClick={(e) => { e.stopPropagation(); del.mutate(id) }}
                    className="p-1 rounded-lg opacity-0 group-hover:opacity-100 hover:text-red-500 text-text-muted transition-all" title="Delete">
                    <Trash2 className="w-3 h-3" />
                  </button>
                </div>
              </div>
              </ContextMenu>
            )
          })}
        </div>
        )}
      </div>
    </aside>
  )
})
