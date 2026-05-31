import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { goalsApi } from '../api/goals.api'
import { tasksApi } from '../api/tasks.api'
import {
  ListTodo,
  Target,
  GitBranch,
} from 'lucide-react'
import { EventTimeline } from '../components/shared/EventTimeline'
import {
  Card,
  Badge,
  SectionHeader,
} from '../components/ui/design'
import { cn } from '../lib/utils'

const STATUS_FILTERS = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'running', label: 'Running' },
  { key: 'in_progress', label: 'In Progress' },
  { key: 'completed', label: 'Completed' },
  { key: 'failed', label: 'Failed' },
]

const STATUS_BADGE = {
  pending: 'default',
  assigned: 'info',
  in_progress: 'warning',
  running: 'info',
  completed: 'success',
  failed: 'danger',
  cancelled: 'default',
}

const STATUS_DOT = {
  pending: 'bg-gray-300',
  assigned: 'bg-blue-400',
  in_progress: 'bg-amber-400',
  running: 'bg-accent',
  completed: 'bg-green-500',
  failed: 'bg-red-500',
  cancelled: 'bg-gray-300',
}

export default function TasksPage() {
  const [filter, setFilter] = useState('all')
  const [selectedTaskId, setSelectedTaskId] = useState(null)

  const { data: goalsData } = useQuery({
    queryKey: ['goals'],
    queryFn: () => goalsApi.list(),
  })

  const { data: tasksData, isLoading } = useQuery({
    queryKey: ['all-tasks'],
    queryFn: () => tasksApi.listAll(),
  })

  const goalMap = useMemo(() => {
    const map = {}
    ;(goalsData?.goals || []).forEach((g) => {
      map[g.id] = g.title || g.id.slice(0, 8)
    })
    return map
  }, [goalsData])

  const allTasks = useMemo(() => tasksData?.tasks || [], [tasksData?.tasks])

  const filteredTasks = useMemo(() => {
    if (filter === 'all') return allTasks
    return allTasks.filter((t) => t.status === filter)
  }, [allTasks, filter])

  const groupedTasks = useMemo(() => {
    const groups = {}
    filteredTasks.forEach((t) => {
      const gid = t.goal_id || 'ungrouped'
      if (!groups[gid]) groups[gid] = []
      groups[gid].push(t)
    })
    return groups
  }, [filteredTasks])

  const statusCounts = useMemo(() => {
    const counts = { all: allTasks.length }
    STATUS_FILTERS.slice(1).forEach(({ key }) => {
      counts[key] = allTasks.filter((t) => t.status === key).length
    })
    return counts
  }, [allTasks])

  const effectiveSelectedTaskId = useMemo(() => {
    if (selectedTaskId && filteredTasks.some((t) => t.id === selectedTaskId)) return selectedTaskId
    return filteredTasks[0]?.id || null
  }, [filteredTasks, selectedTaskId])

  const selectedTask = useMemo(
    () => allTasks.find((t) => t.id === effectiveSelectedTaskId),
    [allTasks, effectiveSelectedTaskId]
  )

  return (
    <div className="h-full flex bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      {/* Left panel */}
      <div className="w-72 shrink-0 border-r border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50 flex flex-col overflow-hidden">
        <div className="p-4 border-b border-gray-100 dark:border-gray-800">
          <SectionHeader title="Tasks" description="" icon={ListTodo} />
        </div>

        <div className="px-3 py-2 border-b border-gray-100 dark:border-gray-800 flex flex-wrap gap-1.5">
          {STATUS_FILTERS.map(({ key, label }) => (
            <button
              key={key}
              onClick={() => setFilter(key)}
              className={cn(
                'px-2 py-1 rounded-full text-[10px] font-medium transition-all border',
                filter === key
                  ? 'bg-accent text-white border-accent'
                  : 'bg-white dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:text-text-primary hover:border-accent/30'
              )}
            >
              {label} {statusCounts[key] || 0}
            </button>
          ))}
        </div>

        <div className="flex-1 overflow-y-auto">
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-5 h-5 border-2 border-accent border-t-transparent rounded-full animate-spin" />
            </div>
          ) : allTasks.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-text-muted">
              <div className="p-3 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-2">
                <ListTodo className="w-5 h-5 text-gray-500 dark:text-gray-400" />
              </div>
              <p className="text-xs">No tasks yet.</p>
            </div>
          ) : Object.keys(groupedTasks).length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-text-muted">
              <div className="p-3 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-2">
                <ListTodo className="w-5 h-5 text-gray-500 dark:text-gray-400" />
              </div>
              <p className="text-xs">No tasks match this filter.</p>
            </div>
          ) : (
            Object.entries(groupedTasks).map(([goalId, goalTasks]) => (
              <div key={goalId}>
                <div className="flex items-center gap-1.5 px-3 py-2 bg-gray-50 dark:bg-gray-800/50 border-b border-gray-100 dark:border-gray-800 sticky top-0">
                  <Target className="w-3 h-3 text-indigo-400 shrink-0" />
                  <span className="text-[10px] font-semibold text-text-muted uppercase tracking-wider truncate">
                    {goalMap[goalId] || goalId.slice(0, 8)}
                  </span>
                  <span className="text-[10px] text-text-muted shrink-0">({goalTasks.length})</span>
                </div>
                {goalTasks.map((t) => (
                  <button
                    key={t.id}
                    onClick={() => setSelectedTaskId(t.id)}
                    className={cn(
                      'w-full text-left px-3 py-2.5 border-b border-gray-100 dark:border-gray-800 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors',
                      effectiveSelectedTaskId === t.id ? 'bg-accent/5 border-l-2 border-l-accent' : ''
                    )}
                  >
                    <div className="flex items-center gap-2">
                      <span className={cn('w-2 h-2 rounded-full shrink-0', STATUS_DOT[t.status] || 'bg-gray-300')} />
                      <span className="text-xs font-medium text-text-primary truncate flex-1">
                        {t.title || t.id.slice(0, 8)}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 mt-1 pl-4">
                      <Badge size="sm" variant={STATUS_BADGE[t.status] || 'default'}>{t.status}</Badge>
                      {t.depends_on?.length > 0 && (
                        <span className="text-[9px] text-text-muted flex items-center gap-0.5">
                          <GitBranch className="w-2.5 h-2.5" />
                          {t.depends_on.length} dep{t.depends_on.length > 1 ? 's' : ''}
                        </span>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            ))
          )}
        </div>
      </div>

      {/* Right panel */}
      <div className="flex-1 overflow-y-auto">
        {selectedTask ? (
          <TaskDetail task={selectedTask} goalMap={goalMap} />
        ) : allTasks.length > 0 ? (
          <div className="flex-1 flex items-center justify-center h-full">
            <p className="text-sm text-text-muted">Select a task to view details</p>
          </div>
        ) : null}
      </div>
    </div>
  )
}

function TaskDetail({ task, goalMap }) {
  const { data: goalData } = useQuery({
    queryKey: ['goal', task.goal_id],
    queryFn: () => goalsApi.get(task.goal_id),
    enabled: !!task.goal_id,
  })

  const { data: eventsData } = useQuery({
    queryKey: ['task-events', task.id],
    queryFn: () => tasksApi.getEvents(task.id),
    enabled: !!task.id,
  })

  const goal = goalData
  const events = eventsData?.events || []

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-5">
      <Card variant="default">
        <div className="p-5">
          <div className="flex items-start justify-between gap-4 mb-3">
            <div className="min-w-0 flex-1">
              <h2 className="text-base font-bold text-text-primary">
                {task.title || task.id.slice(0, 8)}
              </h2>
              {task.goal_id && (
                <p className="text-xs text-text-muted mt-1 flex items-center gap-1">
                  <Target className="w-3 h-3 text-indigo-400" />
                  <span className="font-medium text-indigo-500">{goalMap[task.goal_id] || task.goal_id.slice(0, 8)}</span>
                  {goal && <span className="text-text-muted/50">· {goal.status}</span>}
                </p>
              )}
            </div>
            <Badge size="sm" variant={STATUS_BADGE[task.status] || 'default'}>{task.status}</Badge>
          </div>

          {task.description && (
            <p className="text-sm text-text-secondary leading-relaxed mb-4 whitespace-pre-wrap">{task.description}</p>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <Badge size="sm" variant="default">Priority {task.priority}/5</Badge>
            {task.depends_on?.length > 0 && (
              <Badge size="sm" variant="warning">
                <span className="flex items-center gap-1">
                  <GitBranch className="w-3 h-3" />
                  {task.depends_on.length} upstream task{task.depends_on.length > 1 ? 's' : ''}
                </span>
              </Badge>
            )}
            {task.workspace_path && (
              <Badge size="sm" variant="default">{task.workspace_path.split('/').pop()}</Badge>
            )}
            {task.run_id && (
              <Badge size="sm" variant="info">run/{task.run_id.slice(0, 8)}</Badge>
            )}
          </div>
        </div>
      </Card>

      <EventTimeline events={events} />
    </div>
  )
}
