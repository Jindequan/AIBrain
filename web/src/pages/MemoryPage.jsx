import { useState, useMemo } from 'react'
import { formatRelative } from '../lib/time'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Brain, Trash2, Search, Plus, X, Check,
  CircleAlert, CheckCircle2, Lightbulb, BookOpen,
  ToggleLeft, ToggleRight, AlertTriangle, BarChart3,
} from 'lucide-react'
import { memoryApi } from '../api/memory.api'
import { mutationError } from '../store/toastStore'
import { cn } from '../lib/utils'
import { SectionHeader, Badge, Loading } from '../components/ui/design'

const TYPE_META = {
  fact:         { icon: CheckCircle2, label: 'Fact',         color: 'text-blue-600',   bg: 'bg-blue-500/10',   border: 'border-blue-500/20' },
  preference:   { icon: HeartHand,    label: 'Preference',   color: 'text-pink-500',   bg: 'bg-pink-500/10',   border: 'border-pink-500/20' },
  learning:     { icon: Lightbulb,    label: 'Learning',     color: 'text-amber-500',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  task_outcome: { icon: CircleAlert,  label: 'Task Outcome', color: 'text-green-500',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
}

function HeartHand({ className }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
    </svg>
  )
}




function tokenSimilarity(a, b) {
  const wordsA = new Set(a.toLowerCase().split(/\s+/).filter(w => w.length > 2))
  const wordsB = new Set(b.toLowerCase().split(/\s+/).filter(w => w.length > 2))
  if (wordsA.size === 0 || wordsB.size === 0) return 0
  const intersection = new Set([...wordsA].filter(w => wordsB.has(w)))
  return intersection.size / Math.min(wordsA.size, wordsB.size)
}

function MemoryCard({ entry, conflicts, onDelete, onToggleAuto }) {
  const meta = TYPE_META[entry.type] || TYPE_META.fact
  const Icon = meta.icon
  const hasConflict = conflicts.length > 0

  return (
    <div className={cn(
      'border rounded-2xl bg-white dark:bg-gray-800/50 transition-all overflow-hidden',
      !entry.usable_for_auto_decision ? 'border-dashed border-gray-200 dark:border-gray-700 opacity-60' :
      hasConflict ? 'border-amber-400/40 shadow-sm ring-1 ring-amber-400/10' :
      'border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md'
    )}>
      <div className="p-4">
        <div className="flex items-start gap-3">
          <div className={cn('w-8 h-8 rounded-lg flex items-center justify-center shrink-0', meta.bg)}>
            <Icon className={cn('w-4 h-4', meta.color)} />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span className={cn('text-[11px] font-semibold uppercase tracking-wider', meta.color)}>
                {meta.label}
              </span>
              <Badge size="sm" variant={
                entry.confidence >= 0.7 ? 'success' :
                entry.confidence >= 0.4 ? 'warning' :
                'default'
              }>
                {Math.round(entry.confidence * 100)}%
              </Badge>
              {entry.last_confirmed_at && (
                <span className="text-[10px] text-text-muted font-mono">
                  {formatRelative(entry.last_confirmed_at)}
                </span>
              )}
            </div>
            <p className="text-sm text-text-primary leading-relaxed">{entry.content}</p>
            {hasConflict && (
              <div className="flex items-center gap-1 mt-1.5 text-[10px] text-amber-600 bg-amber-500/5 rounded-lg px-2 py-0.5">
                <AlertTriangle className="w-3 h-3" />
                Similar to: {conflicts.map(c => c.content).join(', ').slice(0, 80)}...
              </div>
            )}
            <div className="flex flex-wrap items-center gap-2 mt-2">
              {entry.tags && entry.tags.length > 0 && entry.tags.map((tag) => (
                <Badge key={tag} size="sm" variant="default">{tag}</Badge>
              ))}
              <button
                onClick={() => onToggleAuto(entry.id, !entry.usable_for_auto_decision)}
                className={cn(
                  'flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-md transition-colors',
                  entry.usable_for_auto_decision
                    ? 'bg-green-100 text-green-700 hover:bg-green-200'
                    : 'bg-gray-100 text-text-muted hover:bg-gray-200'
                )}
                title={entry.usable_for_auto_decision ? 'Used for auto-decisions' : 'Not used for auto-decisions'}
              >
                {entry.usable_for_auto_decision ? <ToggleRight className="w-3 h-3" /> : <ToggleLeft className="w-3 h-3" />}
                {entry.usable_for_auto_decision ? 'Auto' : 'Manual'}
              </button>
            </div>
            <div className="flex items-center gap-2 mt-2 text-[10px] text-text-muted">
              <span className="font-mono">{formatRelative(entry.created_at)}</span>
              {entry.source_session_id && (
                <>
                  <span>·</span>
                  <span className="font-mono truncate max-w-[120px]">{entry.source_session_id}</span>
                </>
              )}
              {entry.source_detail && (
                <>
                  <span>·</span>
                  <span className="truncate max-w-[100px]">{entry.source_detail}</span>
                </>
              )}
            </div>
          </div>
          <button
            onClick={() => onDelete(entry.id)}
            className="p-1.5 rounded-lg hover:bg-red-50 text-text-muted hover:text-red-500 transition-colors shrink-0"
            title="Delete"
          >
            <Trash2 className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  )
}

function CreateMemoryForm({ onDone }) {
  const queryClient = useQueryClient()
  const [type, setType] = useState('fact')
  const [content, setContent] = useState('')
  const [tags, setTags] = useState('')
  const [error, setError] = useState('')

  const createMutation = useMutation({
    mutationFn: () => memoryApi.create({
      type,
      content: content.trim(),
      tags: tags.split(',').map(t => t.trim()).filter(Boolean),
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['memory'] })
      onDone()
    },
    onError: (err) => {
      setError(err?.message || 'Failed to create')
    },
  })

  return (
    <div className="border border-accent/40 rounded-2xl bg-white dark:bg-gray-800/80 shadow-lg overflow-hidden mb-4">
      <div className="flex items-center justify-between px-5 py-3 border-b border-gray-100 dark:border-gray-800">
        <div className="flex items-center gap-2">
          <Plus className="w-4 h-4 text-accent" />
          <h3 className="text-sm font-bold text-text-primary">Add Memory</h3>
        </div>
        <button onClick={onDone} className="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted">
          <X className="w-4 h-4" />
        </button>
      </div>
      <div className="px-5 py-4 space-y-3">
        <div className="flex gap-2">
          {Object.entries(TYPE_META).map(([key, meta]) => (
            <button key={key} onClick={() => setType(key)}
              className={cn('px-3 py-1.5 text-xs font-medium rounded-xl border transition-colors',
                type === key ? meta.bg + ' ' + meta.color + ' ' + meta.border : 'bg-gray-50 dark:bg-gray-800/30 text-text-muted border-transparent'
              )}>
              {meta.label}
            </button>
          ))}
        </div>
        <textarea value={content} onChange={(e) => setContent(e.target.value)}
          placeholder="What do you want to remember? (e.g. User prefers dark mode, Project uses Elixir/Phoenix...)"
          rows={3}
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent resize-none" />
        <input value={tags} onChange={(e) => setTags(e.target.value)}
          placeholder="Tags (comma-separated, e.g. tech-stack, preference)"
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent" />
        {error && <p className="text-xs text-red-500">{error}</p>}
        <div className="flex justify-end">
          <button onClick={() => createMutation.mutate()} disabled={!content.trim() || createMutation.isPending}
            className="flex items-center gap-1.5 px-4 py-2 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 disabled:opacity-50">
            <Check className="w-3.5 h-3.5" /> Save Memory
          </button>
        </div>
      </div>
    </div>
  )
}

export default function MemoryPage() {
  const queryClient = useQueryClient()
  const [typeFilter, setTypeFilter] = useState('')
  const [searchText, setSearchText] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [showSimilar, setShowSimilar] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['memory', typeFilter],
    queryFn: () => memoryApi.list(typeFilter || undefined),
  })

  const delMutation = useMutation({
    mutationFn: (id) => memoryApi.delete(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['memory'] }),
    onError: mutationError('Delete failed'),
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, body }) => memoryApi.update(id, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['memory'] }),
    onError: mutationError('Update failed'),
  })

  const entries = (data?.entries || []).filter((e) =>
    !searchText || e.content.toLowerCase().includes(searchText.toLowerCase())
  )

  const similarEntries = useMemo(() => {
    const result = new Map()
    for (let i = 0; i < entries.length; i++) {
      for (let j = i + 1; j < entries.length; j++) {
        const sim = tokenSimilarity(entries[i].content, entries[j].content)
        if (sim > 0.5) {
          if (!result.has(entries[i].id)) result.set(entries[i].id, [])
          if (!result.has(entries[j].id)) result.set(entries[j].id, [])
          result.get(entries[i].id).push(entries[j])
          result.get(entries[j].id).push(entries[i])
        }
      }
    }
    return result
  }, [entries])

  const matchedSimilarEntries = entries.filter(e => similarEntries.has(e.id))

  const stats = {
    total: entries.length,
    fact: entries.filter((e) => e.type === 'fact').length,
    preference: entries.filter((e) => e.type === 'preference').length,
    learning: entries.filter((e) => e.type === 'learning').length,
    task_outcome: entries.filter((e) => e.type === 'task_outcome').length,
    avgConfidence: entries.length > 0
      ? Math.round(entries.reduce((sum, e) => sum + (e.confidence || 0), 0) / entries.length * 100)
      : 0,
    autoCount: entries.filter(e => e.usable_for_auto_decision).length,
    similarCount: matchedSimilarEntries.length,
  }

  const displayEntries = showSimilar ? matchedSimilarEntries : entries

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-5xl mx-auto px-6 py-8">
        <div className="flex items-center justify-between">
          <SectionHeader title="Memory" description="Knowledge distilled from conversations" icon={Brain} />
          <button onClick={() => setShowCreate(!showCreate)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 transition-colors">
            <Plus className="w-3.5 h-3.5" /> Add Memory
          </button>
        </div>

        {/* Stats bar */}
        {!isLoading && entries.length > 0 && (
          <div className="grid grid-cols-4 gap-3 mt-6 mb-2">
            <StatBadge label="Total" value={stats.total} icon={BookOpen} />
            <StatBadge label="Avg Confidence" value={`${stats.avgConfidence}%`} icon={BarChart3} />
            <StatBadge label="Auto-used" value={`${stats.autoCount}/${stats.total}`} icon={ToggleRight} />
            <button onClick={() => setShowSimilar(!showSimilar)}
              className={cn('rounded-xl px-4 py-3 border text-left transition-all',
                showSimilar ? 'border-amber-400/40 bg-amber-500/5 ring-1 ring-amber-400/10' : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 hover:border-amber-400/30'
              )}>
              <div className={cn('text-2xl font-bold', stats.similarCount > 0 ? 'text-amber-600' : 'text-text-muted')}>{stats.similarCount}</div>
              <div className="text-xs text-text-muted mt-0.5 flex items-center gap-1">
                <AlertTriangle className="w-3 h-3" /> Similar
              </div>
            </button>
          </div>
        )}

        {/* Type filter chips */}
        <div className="flex flex-wrap items-center gap-2 mb-4 mt-4">
          <button
            onClick={() => setTypeFilter('')}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium transition-all border',
              !typeFilter
                ? 'bg-accent text-white border-accent shadow-sm'
                : 'bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700 text-text-secondary hover:text-text-primary hover:border-accent/30'
            )}
          >
            <BookOpen className="w-3.5 h-3.5" /> All ({entries.length})
          </button>
          {Object.entries(TYPE_META).map(([key, meta]) => {
            const Icon = meta.icon
            return (
              <button
                key={key}
                onClick={() => setTypeFilter(key)}
                className={cn(
                  'flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium transition-all border',
                  typeFilter === key
                    ? meta.bg + ' ' + meta.color + ' border-current/30 shadow-sm'
                    : 'bg-white dark:bg-gray-800 border-gray-200 dark:border-gray-700 text-text-secondary hover:text-text-primary hover:border-accent/30'
                )}
              >
                <Icon className="w-3.5 h-3.5" /> {meta.label} ({stats[key]})
              </button>
            )
          })}
        </div>

        {/* Search */}
        <div className="relative mb-4">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted" />
          <input
            type="text"
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            placeholder="Search memory entries..."
            className="w-full bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl pl-9 pr-4 py-2.5 text-sm text-text-primary placeholder:text-muted focus:outline-none focus:border-accent/50 transition-colors"
          />
        </div>

        {showCreate && <CreateMemoryForm onDone={() => setShowCreate(false)} />}

        {/* Entries list */}
        {isLoading ? (
          <Loading text="Loading..." />
        ) : displayEntries.length === 0 ? (
          <div className="flex flex-col items-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <Brain className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm">
              {showSimilar ? 'No similar entries detected.' :
               typeFilter ? `No ${typeFilter} entries.` :
               'No memory entries yet.'}
            </p>
            {!showSimilar && !typeFilter && (
              <p className="text-xs text-text-muted mt-1">Knowledge is distilled from conversations, or add entries manually.</p>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {displayEntries.map((entry) => (
              <MemoryCard
                key={entry.id}
                entry={entry}
                conflicts={similarEntries.get(entry.id) || []}
                onDelete={(id) => delMutation.mutate(id)}
                onToggleAuto={(id, value) => updateMutation.mutate({ id, body: { usable_for_auto_decision: value } })}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

function StatBadge({ label, value, icon: Icon }) {
  return (
    <div className="rounded-xl px-4 py-3 border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50">
      <div className="flex items-center gap-2">
        {Icon && <Icon className="w-4 h-4 text-text-muted" />}
        <span className="text-2xl font-bold text-text-primary">{value}</span>
      </div>
      <div className="text-xs text-text-muted mt-0.5">{label}</div>
    </div>
  )
}
