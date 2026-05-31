import { useState, useMemo, useRef, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { goalsApi } from '../api/goals.api'
import { tasksApi } from '../api/tasks.api'
import GraphView from '../components/graph/GraphView'
import {
  Target, AlertCircle, ListTodo, X, ChevronRight, Plus, Pause, Play, RefreshCw,
  Edit3, Trash2, Check, Zap, BookOpen, RotateCw, FileText
} from 'lucide-react'
import { EventTimeline } from '../components/shared/EventTimeline'
import { Badge, SectionHeader } from '../components/ui/design'
import { cn } from '../lib/utils'
import { Loading } from '../components/ui/design'
import { useToastStore } from '../store/toastStore'

const STATUS_OPTIONS = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'paused', label: 'Paused' },
  { key: 'completed', label: 'Completed' },
  { key: 'archived', label: 'Archived' },
]

const STATUS_BADGE = {
  active: 'success',
  paused: 'warning',
  completed: 'success',
  archived: 'default',
}

export default function GoalsPage() {
  const queryClient = useQueryClient()
  const addToast = useToastStore((s) => s.addToast)
  const [filter, setFilter] = useState('all')
  const [selectedGoalId, setSelectedGoalId] = useState(null)
  const [viewMode, setViewMode] = useState('cards')
  const [showCreate, setShowCreate] = useState(false)
  const containerRef = useRef(null)
  const [dims, setDims] = useState({ width: 800, height: 500 })

  useEffect(() => {
    function resize() {
      if (containerRef.current) {
        const rect = containerRef.current.getBoundingClientRect()
        setDims({ width: rect.width - 4, height: Math.max(400, rect.height - 120) })
      }
    }
    resize()
    window.addEventListener('resize', resize)
    return () => window.removeEventListener('resize', resize)
  }, [])

  const { data: goalsData, isLoading, isError } = useQuery({
    queryKey: ['goals'],
    queryFn: () => goalsApi.list(),
  })

  const { data: allTasksData } = useQuery({
    queryKey: ['all-tasks'],
    queryFn: () => tasksApi.listAll(),
  })

  const scanMutation = useMutation({
    mutationFn: () => goalsApi.scan(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['goals'] })
    },
    onError: (e) => addToast({ title: 'Scan failed', message: e.message, variant: 'error' }),
  })

  const allTasks = useMemo(() => allTasksData?.tasks || [], [allTasksData?.tasks])

  const taskCountByGoal = useMemo(() => {
    const map = {}
    allTasks.forEach((t) => {
      const gid = t.goal_id || 'ungrouped'
      map[gid] = (map[gid] || 0) + 1
    })
    return map
  }, [allTasks])

  const filteredGoals = useMemo(() => {
    const goals = goalsData?.goals || []
    if (filter === 'all') return goals
    return goals.filter((g) => g.status === filter)
  }, [goalsData, filter])

  const statusCounts = useMemo(() => {
    const goals = goalsData?.goals || []
    const counts = { all: goals.length }
    STATUS_OPTIONS.slice(1).forEach(({ key }) => {
      counts[key] = goals.filter((g) => g.status === key).length
    })
    return counts
  }, [goalsData])

  const selectedGoal = useMemo(
    () => (goalsData?.goals || []).find((g) => g.id === selectedGoalId),
    [goalsData, selectedGoalId]
  )

  const graphData = useMemo(() => {
    const goals = goalsData?.goals || []
    const nodes = goals.map((g) => ({
      id: g.id,
      label: g.title || g.id.slice(0, 8),
      subtitle: g.status,
      type: 'goal',
      status: g.status,
      data: g,
    }))
    const edges = goals.filter((g) => g.parent_id).map((g) => ({ source: g.parent_id, target: g.id }))
    return { nodes, edges }
  }, [goalsData])

  if (isLoading) {
    return (
      <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20 flex items-center justify-center">
        <Loading text="Loading goals..." />
      </div>
    )
  }

  if (isError) {
    return (
      <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20 flex flex-col items-center justify-center">
        <AlertCircle className="w-10 h-10 text-red-400 mb-3" />
        <p className="text-sm text-red-500">Failed to load goals.</p>
      </div>
    )
  }

  const goals = goalsData?.goals || []

  return (
    <div ref={containerRef} className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-6 pt-6 pb-0 shrink-0 max-w-5xl mx-auto w-full">
        <SectionHeader title="Goals" description="Track and manage goals" icon={Target} />
        <div className="flex items-center gap-2">
          <button onClick={() => scanMutation.mutate()}
            disabled={scanMutation.isPending}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-xl border border-gray-200 dark:border-gray-700 text-text-secondary hover:text-text-primary hover:border-accent/30 transition-colors">
            <RefreshCw className={cn('w-3.5 h-3.5', scanMutation.isPending && 'animate-spin')} />
            Scan
          </button>
          <div className="flex rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden text-xs bg-white dark:bg-gray-800">
            <button onClick={() => setViewMode('cards')} className={cn('px-3.5 py-1.5 transition-colors font-medium', viewMode === 'cards' ? 'bg-accent text-white' : 'text-text-muted hover:text-text-primary')}>Cards</button>
            <button onClick={() => setViewMode('graph')} className={cn('px-3.5 py-1.5 transition-colors font-medium', viewMode === 'graph' ? 'bg-accent text-white' : 'text-text-muted hover:text-text-primary')}>Graph</button>
          </div>
          <button onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 transition-colors">
            <Plus className="w-3.5 h-3.5" /> New Goal
          </button>
        </div>
      </div>

      {/* Status filter chips */}
      <div className="flex items-center gap-2 px-6 pt-4 pb-4 shrink-0 max-w-5xl mx-auto w-full">
        {STATUS_OPTIONS.map(({ key, label }) => (
          <button key={key} onClick={() => { setFilter(key); setSelectedGoalId(null) }}
            className={cn('px-3 py-1.5 rounded-xl text-xs font-medium transition-all border',
              filter === key ? 'bg-accent text-white border-accent shadow-sm' : 'bg-white dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:text-text-primary hover:border-accent/30'
            )}>
            {label} {statusCounts[key] || 0}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto pb-8 max-w-5xl mx-auto w-full px-6">
        {goals.length === 0 && !showCreate && (
          <div className="flex flex-col items-center justify-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <Target className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm mb-4">No goals yet. Create your first long-term goal.</p>
            <button onClick={() => setShowCreate(true)}
              className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-xl bg-accent text-white hover:bg-accent/90">
              <Plus className="w-4 h-4" /> Create Goal
            </button>
          </div>
        )}

        {showCreate && <CreateGoalForm onDone={() => setShowCreate(false)} />}

        {viewMode === 'graph' && goals.length > 0 ? (
          <div className="h-full min-h-[400px] border border-gray-200 dark:border-gray-700 rounded-2xl bg-white dark:bg-gray-800/50 shadow-sm">
            <GraphView nodes={graphData.nodes} edges={graphData.edges} selectedId={selectedGoalId}
              onNodeClick={(node) => setSelectedGoalId((prev) => prev === node.id ? null : node.id)}
              width={dims.width} height={dims.height} />
          </div>
        ) : (
          <div className="space-y-3">
            {filteredGoals.map((g) => (
              <GoalCard key={g.id} goal={g} isSelected={selectedGoalId === g.id}
                taskCount={taskCountByGoal[g.id] || 0}
                onSelect={() => setSelectedGoalId((prev) => prev === g.id ? null : g.id)} />
            ))}

            {selectedGoal && selectedGoalId && (
              <GoalDetail goal={selectedGoal} onClose={() => setSelectedGoalId(null)} />
            )}
          </div>
        )}
      </div>
    </div>
  )
}

function CreateGoalForm({ onDone }) {
  const queryClient = useQueryClient()
  const addToast = useToastStore((s) => s.addToast)
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [priority, setPriority] = useState(3)

  const createMutation = useMutation({
    mutationFn: () => goalsApi.create({ title, description, priority, status: 'active' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['goals'] })
      onDone()
    },
    onError: (e) => addToast({ title: 'Create failed', message: e.message, variant: 'error' }),
  })

  return (
    <div className="border border-accent/40 rounded-2xl bg-white dark:bg-gray-800/80 shadow-lg overflow-hidden mb-4">
      <div className="flex items-center justify-between px-5 py-3 border-b border-gray-100 dark:border-gray-800">
        <div className="flex items-center gap-2">
          <Plus className="w-4 h-4 text-accent" />
          <h3 className="text-sm font-bold text-text-primary">New Goal</h3>
        </div>
        <button onClick={onDone} className="p-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted">
          <X className="w-4 h-4" />
        </button>
      </div>
      <div className="px-5 py-4 space-y-3">
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Goal title"
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent" />
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Description (optional)" rows={2}
          className="w-full px-3 py-2 text-sm border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent resize-none" />
        <div className="flex items-center gap-3">
          <span className="text-xs text-text-muted">Priority:</span>
          {[1, 2, 3, 4, 5].map(p => (
            <button key={p} onClick={() => setPriority(p)}
              className={cn('w-7 h-7 rounded-lg text-xs font-medium transition-colors',
                p === priority ? 'bg-accent text-white' : 'bg-gray-100 dark:bg-gray-800 text-text-muted hover:text-text-primary'
              )}>{p}</button>
          ))}
        </div>
        <div className="flex justify-end">
          <button onClick={() => createMutation.mutate()} disabled={!title.trim()}
            className="flex items-center gap-1.5 px-4 py-2 text-xs font-medium rounded-xl bg-accent text-white hover:bg-accent/90 disabled:opacity-50">
            <Check className="w-3.5 h-3.5" /> Create
          </button>
        </div>
      </div>
    </div>
  )
}

function GoalCard({ goal, isSelected, taskCount, onSelect }) {
  const automation = goal.automation || {}
  const strategy = goal.strategy || {}
  const strategyAssessment = strategy.assessment || strategy.current_assessment || ''
  const hasStrategy = strategyAssessment || strategy.next_actions?.length > 0

  return (
    <button onClick={onSelect}
      className={cn('w-full text-left border rounded-2xl p-5 transition-all bg-white dark:bg-gray-800/50',
        isSelected ? 'border-accent bg-accent/5 shadow-md' : 'border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md hover:border-accent/30'
      )}>
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-semibold text-text-primary truncate">{goal.title}</h3>
          {goal.description && <p className="text-xs text-text-secondary mt-1 line-clamp-2">{goal.description}</p>}
          <div className="flex items-center gap-3 mt-2">
            <Badge size="sm" variant={STATUS_BADGE[goal.status] || 'default'}>{goal.status}</Badge>
            <span className="text-[10px] text-text-muted">Priority: {goal.priority}/5</span>
            <span className="text-[10px] text-text-muted">{taskCount} task{taskCount !== 1 ? 's' : ''}</span>
            {automation.autonomous && (
              <span className="text-[10px] text-accent font-medium flex items-center gap-0.5">
                <Zap className="w-3 h-3" /> L{automation.autonomy_level}
              </span>
            )}
          </div>
          {hasStrategy && (
            <div className="mt-2 text-[10px] text-text-muted truncate">
              {strategyAssessment && <span>Strategy: {strategyAssessment.slice(0, 80)}</span>}
              {strategy.next_actions?.length > 0 && <span> · Next: {strategy.next_actions[0]}</span>}
            </div>
          )}
        </div>
        <ChevronRight className={cn('w-4 h-4 shrink-0 mt-1 transition-transform', isSelected ? 'rotate-90 text-accent' : 'text-text-muted')} />
      </div>
    </button>
  )
}

function GoalDetail({ goal, onClose }) {
  const queryClient = useQueryClient()
  const [editing, setEditing] = useState(false)
  const [editTitle, setEditTitle] = useState(goal.title)
  const [editDesc, setEditDesc] = useState(goal.description || '')

  const automation = goal.automation || {}
  const strategy = goal.strategy || {}
  const strategyAssessment = strategy.assessment || strategy.current_assessment || ''

  const { data: tasksData } = useQuery({
    queryKey: ['goal-tasks', goal.id],
    queryFn: () => tasksApi.listByGoal(goal.id),
    enabled: !!goal.id,
  })

  const { data: eventsData } = useQuery({
    queryKey: ['goal-events', goal.id],
    queryFn: () => goalsApi.getEvents(goal.id),
    enabled: !!goal.id,
  })

  const { data: runsData } = useQuery({
    queryKey: ['goal-runs', goal.id],
    queryFn: () => goalsApi.getRuns(goal.id),
    enabled: !!goal.id,
  })

  const { data: memoriesData } = useQuery({
    queryKey: ['goal-memories', goal.id],
    queryFn: () => goalsApi.getMemories(goal.id),
    enabled: !!goal.id,
  })

  const updateMutation = useMutation({
    mutationFn: (params) => goalsApi.update(goal.id, params),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['goals'] }),
  })

  const deleteMutation = useMutation({
    mutationFn: () => goalsApi.delete(goal.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['goals'] })
      onClose()
    },
  })

  const tasks = tasksData?.tasks || []
  const events = eventsData?.events || []
  const runs = runsData?.runs || []
  const memories = memoriesData?.memories || []

  function handleSaveEdit() {
    updateMutation.mutate({ title: editTitle, description: editDesc })
    setEditing(false)
  }

  function handleTogglePause() {
    updateMutation.mutate({ status: goal.status === 'active' ? 'paused' : 'active' })
  }

  function handleSetAutonomy(level) {
    updateMutation.mutate({
      metadata: { ...(goal.metadata || {}), autonomy_level: level, autonomous: level > 0 }
    })
  }

  return (
    <div className="border border-accent/40 rounded-2xl bg-white dark:bg-gray-800/80 shadow-lg overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100 dark:border-gray-800 bg-gradient-to-r from-accent/[0.03] to-transparent">
        <div className="min-w-0 flex-1">
          {editing ? (
            <div className="space-y-2">
              <input value={editTitle} onChange={(e) => setEditTitle(e.target.value)}
                className="w-full px-2 py-1 text-sm border border-gray-200 dark:border-gray-700 rounded-lg bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent" />
              <textarea value={editDesc} onChange={(e) => setEditDesc(e.target.value)} rows={2}
                className="w-full px-2 py-1 text-xs border border-gray-200 dark:border-gray-700 rounded-lg bg-white dark:bg-gray-800 text-text-primary focus:outline-none focus:border-accent resize-none" />
              <div className="flex gap-2">
                <button onClick={handleSaveEdit} className="flex items-center gap-1 px-2.5 py-1 text-[10px] font-medium rounded-lg bg-accent text-white">
                  <Check className="w-3 h-3" /> Save
                </button>
                <button onClick={() => setEditing(false)} className="px-2.5 py-1 text-[10px] text-text-muted rounded-lg hover:bg-gray-100">Cancel</button>
              </div>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-2">
                <Target className="w-4 h-4 text-accent shrink-0" />
                <h2 className="text-base font-bold text-text-primary truncate">{goal.title}</h2>
              </div>
              {goal.description && <p className="text-xs text-text-secondary mt-1">{goal.description}</p>}
              <div className="flex items-center gap-2 mt-2">
                <Badge size="sm" variant={STATUS_BADGE[goal.status] || 'default'}>{goal.status}</Badge>
                <Badge size="sm" variant="warning">Priority: {goal.priority}/5</Badge>
                {automation.autonomous && (
                  <Badge size="sm" variant="info">Autonomous L{automation.autonomy_level}</Badge>
                )}
              </div>
            </>
          )}
        </div>
        <div className="flex gap-1.5 shrink-0">
          <button onClick={() => setEditing(true)} className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted" title="Edit">
            <Edit3 className="w-3.5 h-3.5" />
          </button>
          <button onClick={handleTogglePause} className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted" title={goal.status === 'active' ? 'Pause' : 'Resume'}>
            {goal.status === 'active' ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5" />}
          </button>
          <button onClick={() => { if (confirm('Delete this goal?')) deleteMutation.mutate() }}
            className="p-1.5 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/20 text-text-muted hover:text-red-500" title="Delete">
            <Trash2 className="w-3.5 h-3.5" />
          </button>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-text-muted">
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      <div className="px-5 py-4 space-y-5">
        {/* Autonomy settings */}
        <div>
          <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 flex items-center gap-1.5">
            <Zap className="w-3.5 h-3.5" /> Autonomy Level
          </h3>
          <div className="flex gap-2">
            {[
              { level: 0, label: 'Manual' },
              { level: 1, label: 'Semi-Auto' },
              { level: 2, label: 'Autonomous' },
            ].map(({ level, label }) => (
              <button key={level} onClick={() => handleSetAutonomy(level)}
                className={cn('flex-1 px-3 py-2 rounded-xl text-xs font-medium transition-colors border',
                  automation.autonomy_level === level
                    ? 'bg-accent/10 text-accent border-accent/30'
                    : 'bg-gray-50 dark:bg-gray-800/30 text-text-muted border-transparent hover:border-accent/20'
                )}>
                {label}
                <div className="text-[10px] mt-0.5">{level === 0 ? 'You trigger runs' : level === 1 ? 'AI suggests, you approve' : 'AI runs independently'}</div>
              </button>
            ))}
          </div>
        </div>

        {/* Strategy */}
        {(strategyAssessment || strategy.next_actions?.length > 0 || strategy.blockers?.length > 0) && (
          <div>
            <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <RotateCw className="w-3.5 h-3.5" /> Current Strategy
            </h3>
            <div className="bg-gray-50 dark:bg-gray-800/30 rounded-xl px-3 py-2 space-y-1.5 text-xs">
              {strategyAssessment && <div><span className="text-text-muted font-medium">Assessment:</span> <span className="text-text-primary">{strategyAssessment}</span></div>}
              {strategy.next_actions?.length > 0 && (
                <div><span className="text-text-muted font-medium">Next actions:</span> {strategy.next_actions.join(', ')}</div>
              )}
              {strategy.blockers?.length > 0 && (
                <div className="text-red-500"><span className="font-medium">Blockers:</span> {strategy.blockers.join(', ')}</div>
              )}
            </div>
          </div>
        )}

        {/* Tasks */}
        <div>
          <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 flex items-center gap-1.5">
            <ListTodo className="w-3.5 h-3.5" /> Tasks ({tasks.length})
          </h3>
          {tasks.length === 0 ? (
            <p className="text-xs text-text-muted py-3 text-center bg-gray-50 dark:bg-gray-800/30 rounded-lg">No tasks.</p>
          ) : (
            <div className="space-y-1">
              {tasks.slice(0, 10).map((task) => (
                <div key={task.id} className="flex items-center gap-2 px-3 py-1.5 bg-gray-50 dark:bg-gray-800/30 rounded-lg text-xs">
                  <span className={cn('w-2 h-2 rounded-full shrink-0',
                    task.status === 'completed' ? 'bg-green-500' :
                    task.status === 'running' ? 'bg-accent' : 'bg-gray-300'
                  )} />
                  <span className="text-text-primary flex-1 truncate">{task.title || task.id.slice(0, 8)}</span>
                  <Badge size="sm" variant={task.status === 'completed' ? 'success' : task.status === 'failed' ? 'danger' : 'default'}>{task.status}</Badge>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Recent Runs */}
        {runs.length > 0 && (
          <div>
            <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <FileText className="w-3.5 h-3.5" /> Recent Runs ({runs.length})
            </h3>
            <div className="space-y-1">
              {runs.slice(0, 5).map((run) => (
                <div key={run.id} className="flex items-center gap-2 px-3 py-1.5 bg-gray-50 dark:bg-gray-800/30 rounded-lg text-xs">
                  <span className={cn('w-2 h-2 rounded-full shrink-0',
                    run.status === 'completed' ? 'bg-green-500' :
                    run.status === 'failed' ? 'bg-red-500' :
                    run.status === 'running' ? 'bg-accent' : 'bg-gray-300'
                  )} />
                  <span className="text-text-primary flex-1 truncate">{run.objective || run.title || 'Untitled run'}</span>
                  <span className="text-text-muted text-[10px]">{run.status}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Memories */}
        {memories.length > 0 && (
          <div>
            <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <BookOpen className="w-3.5 h-3.5" /> Memories ({memories.length})
            </h3>
            <div className="space-y-1">
              {memories.slice(0, 5).map((mem) => (
                <div key={mem.id} className="px-3 py-2 bg-gray-50 dark:bg-gray-800/30 rounded-lg text-xs">
                  <div className="text-text-primary truncate">{mem.narrative || mem.objective || 'Memory'}</div>
                  {mem.lessons?.length > 0 && (
                    <div className="text-text-muted mt-0.5 text-[10px]">Lessons: {mem.lessons.slice(0, 2).join('; ')}</div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        <EventTimeline events={events} taskTitleMap={Object.fromEntries(tasks.map(t => [t.id, t.title || t.id.slice(0, 8)]))} />
      </div>
    </div>
  )
}
