import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Clock, Plus, X, Pause, Play, Trash2, RefreshCw, Check,
  ChevronRight
} from 'lucide-react'
import { schedulerApi } from '../api/scheduler.api'
import { mutationError } from '../store/toastStore'
import { goalsApi } from '../api/goals.api'
import { channelsApi } from '../api/channels.api'
import { cn } from '../lib/utils'
import { SectionHeader, Badge, Loading } from '../components/ui/design'

const STATUSES = ['all', 'active', 'paused', 'completed', 'cancelled']
const TRIGGER_TYPES = [
  { value: 'cron', label: 'Cron Schedule' },
]

function formatRelativeTime(iso) {
  if (!iso) return '—'
  const d = new Date(iso)
  const now = new Date()
  const diff = d - now
  if (diff < 0) return 'overdue'
  if (diff < 60000) return 'in <1m'
  if (diff < 3600000) return `in ${Math.floor(diff / 60000)}m`
  if (diff < 86400000) return `in ${Math.floor(diff / 3600000)}h`
  return `in ${Math.floor(diff / 86400000)}d`
}

export default function SchedulerPage() {
  const queryClient = useQueryClient()
  const [statusFilter, setStatusFilter] = useState('all')
  const [selectedId, setSelectedId] = useState(null)
  const [showCreate, setShowCreate] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['scheduler'],
    queryFn: () => schedulerApi.list(),
    refetchInterval: 15000,
  })

  const scanMutation = useMutation({
    mutationFn: () => schedulerApi.scan(),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['scheduler'] }),
    onError: mutationError('Scan failed'),
  })

  const deleteMutation = useMutation({
    mutationFn: (id) => schedulerApi.delete(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['scheduler'] }),
    onError: mutationError('Delete schedule failed'),
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, status }) => schedulerApi.update(id, { status }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['scheduler'] }),
    onError: mutationError('Toggle schedule failed'),
  })

  const rules = (data?.automation_rules || [])
    .filter((r) => statusFilter === 'all' || r.status === statusFilter)
    .sort((a, b) => {
      const aTime = a.next_fire_at ? new Date(a.next_fire_at).getTime() : Infinity
      const bTime = b.next_fire_at ? new Date(b.next_fire_at).getTime() : Infinity
      return aTime - bTime
    })

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-5xl mx-auto px-6 py-8">
        <div className="flex items-center justify-between">
          <SectionHeader title="Scheduler" description="Automated tasks and reminders" icon={Clock} />
          <div className="flex gap-2">
            <button onClick={() => scanMutation.mutate()}
              disabled={scanMutation.isPending}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-xl border border-gray-200 dark:border-gray-700 text-text-secondary hover:text-text-primary hover:border-accent/30 transition-colors">
              <RefreshCw className={cn('w-3.5 h-3.5', scanMutation.isPending && 'animate-spin')} />
              Scan Now
            </button>
            <button onClick={() => setShowCreate(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 transition-colors">
              <Plus className="w-3.5 h-3.5" /> New Schedule
            </button>
          </div>
        </div>

        {/* Status filter */}
        <div className="flex items-center gap-2 mb-4 mt-6">
          {STATUSES.map((s) => (
            <button key={s} onClick={() => setStatusFilter(s)}
              className={cn('px-3 py-1.5 rounded-xl text-xs font-medium transition-all border',
                statusFilter === s ? 'bg-accent text-white border-accent shadow-sm' : 'bg-white dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:text-text-primary hover:border-accent/30'
              )}>
              {s.charAt(0).toUpperCase() + s.slice(1)}
            </button>
          ))}
          {data?.automation_rules && (
            <span className="ml-auto text-xs text-text-muted">{rules.length} items</span>
          )}
        </div>

        {showCreate && (
          <CreateScheduleForm
            onDone={() => setShowCreate(false)}
          />
        )}

        {isLoading ? (
          <Loading text="Loading..." />
        ) : rules.length === 0 ? (
          <div className="flex flex-col items-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <Clock className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm">{statusFilter !== 'all' ? `No ${statusFilter} items.` : 'No scheduled items. Create one to get started.'}</p>
          </div>
        ) : (
          <div className="space-y-2">
            {rules.map((rule) => (
              <ScheduleCard
                key={rule.id}
                rule={rule}
                isSelected={selectedId === rule.id}
                onSelect={() => setSelectedId(selectedId === rule.id ? null : rule.id)}
                onPause={() => toggleMutation.mutate({ id: rule.id, status: 'paused' })}
                onResume={() => toggleMutation.mutate({ id: rule.id, status: 'active' })}
                onDelete={() => { if (confirm('Delete?')) deleteMutation.mutate(rule.id) }}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

function ScheduleCard({ rule, isSelected, onSelect, onPause, onResume, onDelete }) {
  const { data: runsData } = useQuery({
    queryKey: ['schedule-runs', rule.id],
    queryFn: () => schedulerApi.getRuns(rule.id),
    enabled: isSelected,
  })

  const runs = runsData?.runs || []

  return (
    <div className={cn(
      'border rounded-2xl bg-white dark:bg-gray-800/50 transition-all overflow-hidden',
      isSelected ? 'border-accent/40 shadow-md' : 'border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md'
    )}>
      <button onClick={onSelect} className="w-full text-left px-5 py-4 flex items-center gap-4">
        <div className={cn('p-2 rounded-xl',
          rule.status === 'active' ? 'bg-green-500/10 text-green-600' :
          rule.status === 'paused' ? 'bg-amber-500/10 text-amber-600' :
          'bg-gray-100 dark:bg-gray-800 text-gray-400'
        )}>
          <Clock className="w-4 h-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-text-primary truncate">{rule.name}</span>
            <Badge size="sm" variant={rule.status === 'active' ? 'success' : rule.status === 'paused' ? 'warning' : 'default'}>{rule.status}</Badge>
          </div>
          <div className="flex items-center gap-3 mt-1 text-[10px] text-text-muted">
            <span className="font-mono">{rule.trigger_type}</span>
            {rule.trigger_config?.cron && <span>{rule.trigger_config.cron}</span>}
            {rule.next_fire_at && <span>{formatRelativeTime(rule.next_fire_at)}</span>}
            {rule.last_fired_at && <span>Last: {formatRelativeTime(rule.last_fired_at)}</span>}
          </div>
        </div>
        <div className="flex gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
          {rule.status === 'active' && (
            <button onClick={onPause} className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted" title="Pause">
              <Pause className="w-3.5 h-3.5" />
            </button>
          )}
          {rule.status === 'paused' && (
            <button onClick={onResume} className="p-1.5 rounded-lg hover:bg-green-100 dark:hover:bg-green-900/20 text-green-600" title="Resume">
              <Play className="w-3.5 h-3.5" />
            </button>
          )}
          <button onClick={onDelete} className="p-1.5 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/20 text-text-muted hover:text-red-500" title="Delete">
            <Trash2 className="w-3.5 h-3.5" />
          </button>
        </div>
        <ChevronRight className={cn('w-4 h-4 shrink-0 text-text-muted transition-transform', isSelected && 'rotate-90')} />
      </button>

      {isSelected && (
        <div className="px-5 pb-4 border-t border-gray-100 dark:border-gray-800 pt-3 space-y-3">
          <div className="grid grid-cols-2 gap-3 text-xs">
            <div>
              <span className="text-text-muted font-medium">Action:</span>
              <span className="ml-1.5 text-text-primary">{rule.action_type}</span>
              {rule.action_config?.title && <span className="ml-1 text-text-secondary">— {rule.action_config.title}</span>}
            </div>
            <div>
              <span className="text-text-muted font-medium">Priority:</span>
              <span className="ml-1.5 text-text-primary">{rule.priority}/5</span>
            </div>
          </div>

          {rule.last_result && (
            <div className="text-xs bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2 text-text-secondary">
              <span className="font-medium text-text-muted">Last result:</span> {rule.last_result}
            </div>
          )}

          {runs.length > 0 && (
            <div>
              <span className="text-xs font-medium text-text-muted">Recent Runs ({runs.length})</span>
              <div className="mt-1 space-y-1">
                {runs.slice(0, 5).map((run) => (
                  <div key={run.id} className="flex items-center gap-2 px-3 py-1.5 bg-gray-50 dark:bg-gray-800/30 rounded-lg text-xs">
                    <span className={cn('w-2 h-2 rounded-full shrink-0',
                      run.status === 'completed' ? 'bg-green-500' :
                      run.status === 'failed' ? 'bg-red-500' : 'bg-gray-300'
                    )} />
                    <span className="text-text-primary flex-1 truncate">{run.objective || run.title || 'Run'}</span>
                    <span className="text-text-muted text-[10px]">{run.status}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function CreateScheduleForm({ onDone }) {
  const queryClient = useQueryClient()
  const [name, setName] = useState('')
  const [triggerType, setTriggerType] = useState('cron')
  const [cronExpr, setCronExpr] = useState('')
  const [message, setMessage] = useState('')
  const [goalId, setGoalId] = useState('')
  const [notifyChannels, setNotifyChannels] = useState([])

  const { data: goalsData } = useQuery({
    queryKey: ['goals'],
    queryFn: () => goalsApi.list({ status: 'active' }),
  })

  const { data: channelsData } = useQuery({
    queryKey: ['channels'],
    queryFn: () => channelsApi.list(),
  })

  const goals = goalsData?.goals || []
  const channels = (channelsData?.configs || []).filter(c => c.enabled)

  const toggleChannel = (channelType) => {
    setNotifyChannels(prev =>
      prev.includes(channelType) ? prev.filter(c => c !== channelType) : [...prev, channelType]
    )
  }

  const createMutation = useMutation({
    mutationFn: () => schedulerApi.create({
      name,
      trigger_type: triggerType,
      trigger_config: triggerType === 'cron' ? { cron: cronExpr } : {},
      action: { type: 'create_task', message, goal_id: goalId || undefined, notify_channels: notifyChannels.length > 0 ? notifyChannels : undefined },
      status: 'active',
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['scheduler'] })
      onDone()
    },
    onError: mutationError('Create schedule failed'),
  })

  return (
    <div className="border border-accent/40 rounded-2xl bg-white dark:bg-gray-800/80 shadow-lg overflow-hidden mb-4">
      <div className="flex items-center justify-between px-5 py-3 border-b border-gray-100 dark:border-gray-800">
        <div className="flex items-center gap-2">
          <Plus className="w-4 h-4 text-accent" />
          <h3 className="text-sm font-bold text-text-primary">New Schedule</h3>
        </div>
        <button onClick={onDone} className="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted">
          <X className="w-4 h-4" />
        </button>
      </div>
      <div className="px-5 py-4 space-y-3">
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Schedule name (e.g. Daily News)"
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent" />
        <div className="flex gap-2">
          {TRIGGER_TYPES.map(tt => (
            <button key={tt.value} onClick={() => setTriggerType(tt.value)}
              className={cn('px-3 py-1.5 text-xs font-medium rounded-xl border transition-colors',
                triggerType === tt.value ? 'bg-accent/10 text-accent border-accent/30' : 'bg-gray-50 dark:bg-gray-800/30 text-text-muted border-transparent'
              )}>
              {tt.label}
            </button>
          ))}
        </div>
        {triggerType === 'cron' && (
          <input value={cronExpr} onChange={(e) => setCronExpr(e.target.value)} placeholder="Cron expression (e.g. 0 9 * * *)"
            className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent font-mono" />
        )}
        <textarea value={message} onChange={(e) => setMessage(e.target.value)} placeholder="What should the AI do? (e.g. Check latest tech news and summarize)" rows={2}
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent resize-none" />
        {goals.length > 0 && (
          <select value={goalId} onChange={(e) => setGoalId(e.target.value)}
            className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent">
            <option value="">No goal binding</option>
            {goals.map(g => (
              <option key={g.id} value={g.id}>{g.title}</option>
            ))}
          </select>
        )}
        {channels.length > 0 && (
          <div>
            <span className="text-xs font-medium text-text-muted">Notify via</span>
            <div className="flex flex-wrap gap-2 mt-1.5">
              {channels.map(ch => (
                <button key={ch.id} type="button" onClick={() => toggleChannel(ch.channel_type)}
                  className={cn('px-2.5 py-1 text-xs font-medium rounded-lg border transition-colors',
                    notifyChannels.includes(ch.channel_type)
                      ? 'bg-accent/10 text-accent border-accent/30'
                      : 'bg-gray-50 dark:bg-gray-800/30 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30'
                  )}>
                  {ch.name || ch.channel_type}
                </button>
              ))}
            </div>
          </div>
        )}
        <div className="flex justify-end">
          <button onClick={() => createMutation.mutate()} disabled={!name.trim() || !message.trim()}
            className="flex items-center gap-1.5 px-4 py-2 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 disabled:opacity-50">
            <Check className="w-3.5 h-3.5" /> Create Schedule
          </button>
        </div>
      </div>
    </div>
  )
}
