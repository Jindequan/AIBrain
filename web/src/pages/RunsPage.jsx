import { useState, useMemo, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Play, List, ChevronRight } from 'lucide-react'
import { runsApi } from '../api/runs.api'
import { cn } from '../lib/utils'
import RunDetail, { STATUS_CONFIG, formatShortTime, sourceTypeLabel } from '../components/run/RunDetail'
import { SectionHeader } from '../components/ui/design'

const ALL_STATUSES = ['all', 'running', 'pending', 'waiting_approval', 'waiting_assistant', 'completed', 'failed', 'cancelled']

// ── Left panel: timeline ──

function TimelineList({ runs, selectedId, onSelect }) {
  return (
    <div className="space-y-0.5">
      {runs.map((r) => {
        const cfg = STATUS_CONFIG[r.status] || STATUS_CONFIG.pending
        const selected = r.run_id === selectedId
        return (
          <button key={r.run_id}
            onClick={() => onSelect(r.run_id)}
            className={cn(
              'w-full text-left px-3 py-2.5 rounded-xl transition-all border',
              selected
                ? 'bg-accent/5 border-accent/30 shadow-sm'
                : 'border-transparent hover:bg-gray-50 dark:hover:bg-gray-800/30'
            )}>
            <div className="flex items-center gap-2.5">
              <div className={cn('p-1.5 rounded-lg shrink-0', cfg.bg, cfg.text)}>
                {<cfg.icon className={cn('w-3.5 h-3.5', r.status === 'running' && 'animate-spin')} />}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5">
                  <span className={cn('text-xs font-medium truncate', selected ? 'text-accent' : 'text-text-primary')}>
                    {sourceTypeLabel(r.source_type)}
                  </span>
                  <span className="text-[10px] text-text-muted shrink-0">{formatShortTime(r.started_at || r.inserted_at)}</span>
                </div>
                {((r.input?.task || r.input?.message) || r.objective) && (
                  <p className="text-[11px] text-text-muted truncate mt-0.5">{r.input?.task || r.input?.message || r.objective}</p>
                )}
              </div>
              <ChevronRight className={cn('w-3.5 h-3.5 shrink-0', selected ? 'text-accent' : 'text-text-muted/50')} />
            </div>
          </button>
        )
      })}
    </div>
  )
}

// ── Main page ──

export default function RunsPage() {
  const [statusFilter, setStatusFilter] = useState('all')
  const [selectedId, setSelectedId] = useState(null)
  const [fullscreen, setFullscreen] = useState(false)

  const { data } = useQuery({
    queryKey: ['runs', statusFilter],
    queryFn: () => runsApi.list(statusFilter !== 'all' ? { status: statusFilter } : undefined),
    refetchOnWindowFocus: true,
    refetchInterval: 5000,
    staleTime: 3000,
  })

  const runs = useMemo(() => data?.runs || [], [data?.runs])
  const selectedRun = useMemo(() => runs.find(r => r.run_id === selectedId), [runs, selectedId])

  const handleSelect = useCallback((id) => {
    setSelectedId(id === selectedId ? null : id)
  }, [selectedId])

  const handleBack = useCallback(() => {
    setSelectedId(null)
  }, [])

  const showDetail = selectedId && selectedRun

  return (
    <div className="h-full flex bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      {(!showDetail || !fullscreen) && (
        <div className="w-80 shrink-0 border-r border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 flex flex-col">
          <div className="px-4 pt-4 pb-2">
            <div className="flex items-center justify-between mb-3">
              <SectionHeader title="Runs" description="" icon={Play} />
              <span className="text-[11px] text-text-muted">{runs.length}</span>
            </div>
            <div className="flex flex-wrap gap-1 pb-1">
              {ALL_STATUSES.map((s) => {
                const active = statusFilter === s
                const cfg = STATUS_CONFIG[s]
                const Icon = cfg?.icon
                return (
                  <button key={s} onClick={() => { setStatusFilter(s); setSelectedId(null) }}
                    className={cn(
                      'flex items-center gap-1 px-2 py-1 rounded text-[10px] font-medium whitespace-nowrap transition-colors border',
                      active
                        ? (cfg ? `${cfg.bg} ${cfg.text} border-current/20` : 'bg-accent/10 text-accent border-accent/30')
                        : 'text-text-muted border-transparent hover:bg-gray-100 dark:hover:bg-gray-800/50'
                    )}>
                    {Icon && <Icon className="w-3 h-3" />}
                    {s === 'all' ? 'All' : cfg?.label || s}
                  </button>
                )
              })}
            </div>
          </div>

          <div className="flex-1 overflow-y-auto px-3 pb-4">
            {runs.length > 0 ? (
              <TimelineList runs={runs} selectedId={selectedId}
                onSelect={handleSelect} />
            ) : (
              <div className="flex flex-col items-center py-16">
                <div className="p-3 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-2">
                  <Play className="w-5 h-5 text-gray-500 dark:text-gray-400" />
                </div>
                <p className="text-xs text-text-muted">No runs</p>
              </div>
            )}
          </div>
        </div>
      )}

      <div className="flex-1 bg-white dark:bg-gray-800/30 min-w-0 flex flex-col relative">
        {showDetail ? (
          <RunDetail run={selectedRun}
            onClose={handleBack}
            fullscreen={fullscreen}
            onToggleFullscreen={() => setFullscreen(!fullscreen)} />
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center">
              <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4 mx-auto w-fit">
                <List className="w-6 h-6 text-gray-500 dark:text-gray-400" />
              </div>
              <p className="text-sm text-text-muted">Select a run to view details</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
