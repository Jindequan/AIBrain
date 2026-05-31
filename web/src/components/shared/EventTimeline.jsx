import { Activity } from 'lucide-react'

const GOAL_COLOR = 'border-indigo-400 bg-indigo-50'
const TASK_COLOR = 'border-amber-400 bg-amber-50'
const DOT_GOAL = 'bg-indigo-400'
const DOT_TASK = 'bg-amber-400'

export function EventTimeline({ events, taskTitleMap }) {
  if (!events || events.length === 0) return null

  const sorted = [...events].sort((a, b) => {
    const da = a.inserted_at ? new Date(a.inserted_at).getTime() : 0
    const db = b.inserted_at ? new Date(b.inserted_at).getTime() : 0
    return db - da
  })

  return (
    <div className="bg-card-bg border border-card-border rounded-xl p-5 shadow-card">
      <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-4 flex items-center gap-1.5">
        <Activity className="w-3.5 h-3.5" />
        Timeline ({sorted.length})
      </h3>
      <div className="relative">
        <div className="absolute left-[9px] top-2 bottom-2 w-0.5 bg-gray-200" />

        <div className="space-y-0">
          {sorted.map((e) => {
            const isTaskEvent = !!e.task_id
            const borderColor = isTaskEvent ? TASK_COLOR : GOAL_COLOR
            const dotColor = isTaskEvent ? DOT_TASK : DOT_GOAL
            const taskName = taskTitleMap && e.task_id ? taskTitleMap[e.task_id] : null

            return (
              <div key={e.id} className="flex gap-3 py-2 relative">
                <div className="shrink-0 mt-1">
                  <div className={`w-[18px] h-[18px] rounded-full border-2 flex items-center justify-center ${borderColor}`}>
                    <div className={`w-2 h-2 rounded-full ${dotColor}`} />
                  </div>
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium text-text-primary">{e.event_type}</span>
                    <span className="text-[10px] text-text-muted shrink-0">
                      {e.inserted_at ? new Date(e.inserted_at).toLocaleString() : ''}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 flex-wrap">
                    {taskName && (
                      <span className="text-[10px] text-amber-600 font-medium">Task: {taskName}</span>
                    )}
                    {!isTaskEvent && (
                      <span className="text-[10px] text-indigo-400 font-medium">Goal-level</span>
                    )}
                    {e.source && (
                      <span className="text-[10px] text-text-muted">via {e.source}</span>
                    )}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
