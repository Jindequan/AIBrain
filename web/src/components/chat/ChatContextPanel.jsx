import { X, MessageSquare, FolderOpen, File, ChevronRight, Target, ListTodo, Activity, ChevronDown } from 'lucide-react'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { fsApi } from '../../api/filesystem.api'
import { goalsApi } from '../../api/goals.api'
import { tasksApi } from '../../api/tasks.api'
import { runsApi } from '../../api/runs.api'
import { cn } from '../../lib/utils'
import RunDetail from '../run/RunDetail'

function FileTree({ path, depth = 0, onFileSelect }) {
  const { data: fsData, isLoading } = useQuery({
    queryKey: ['fs', path],
    queryFn: () => fsApi.list(path),
    enabled: !!path,
    refetchOnWindowFocus: false,
  })

  if (isLoading && depth === 0) {
    return (
      <div className="px-3 py-2 text-xs text-text-muted animate-pulse">
        Loading...
      </div>
    )
  }

  if (!fsData) {
    return (
      <div className="px-3 py-2 text-xs text-text-muted">
        No directory selected
      </div>
    )
  }

  const dirs = fsData.dirs || []
  const files = fsData.files || []

  // Important files to highlight
  const importantFiles = ['README.md', 'package.json', 'README', 'Makefile', 'docker-compose.yml', '.env.example']
  const sortedFiles = [
    ...files.filter(f => importantFiles.includes(f.name)),
    ...files.filter(f => !importantFiles.includes(f.name))
  ].slice(0, 10) // Limit to 10 files

  return (
    <div className={cn(depth > 0 && 'ml-3')}>
      {/* Directories */}
      {dirs.slice(0, 8).map((dir) => (
        <div key={dir.path} className="flex items-center gap-1.5 py-1 px-2 rounded hover:bg-gray-100 dark:hover:bg-gray-800 cursor-pointer group">
          <FolderOpen className="w-3.5 h-3.5 text-accent-gold shrink-0" />
          <span className="text-xs text-text-primary truncate flex-1">{dir.name}</span>
          <ChevronRight className="w-3 h-3 text-text-muted opacity-0 group-hover:opacity-100 shrink-0" />
        </div>
      ))}

      {/* Files */}
      {sortedFiles.map((file) => {
        const isImportant = importantFiles.includes(file.name)
        return (
          <div
            key={file.path}
            onClick={() => onFileSelect?.(file)}
            className={cn(
              "flex items-center gap-1.5 py-1 px-2 rounded hover:bg-gray-100 dark:hover:bg-gray-800 cursor-pointer group",
              isImportant && "font-medium"
            )}
          >
            <File className={cn(
              "w-3.5 h-3.5 shrink-0",
              isImportant ? "text-accent" : "text-text-muted"
            )} />
            <span className={cn(
              "text-xs truncate flex-1",
              isImportant ? "text-text-primary" : "text-text-secondary"
            )}>{file.name}</span>
          </div>
        )
      })}

      {dirs.length > 8 && (
        <div className="px-2 py-1 text-xs text-text-muted">
          +{dirs.length - 8} more directories
        </div>
      )}

      {files.length > 10 && (
        <div className="px-2 py-1 text-xs text-text-muted">
          +{files.length - 10} more files
        </div>
      )}
    </div>
  )
}

export default function ChatContextPanel({ sessionId, workspacePath, onClose }) {
  const [expandedRunId, setExpandedRunId] = useState(null)

  const { data: fsData } = useQuery({
    queryKey: ['fs', workspacePath],
    queryFn: () => fsApi.list(workspacePath),
    enabled: !!workspacePath,
    refetchOnWindowFocus: false,
  })

  // Fetch active goals, tasks, and runs
  const { data: goalsData } = useQuery({
    queryKey: ['goals', 'active'],
    queryFn: () => goalsApi.list({ status: 'active' }),
    refetchOnWindowFocus: false,
  })

  const { data: tasksData } = useQuery({
    queryKey: ['tasks', 'active'],
    queryFn: () => tasksApi.listAll(),
    refetchOnWindowFocus: false,
  })

  const { data: runsData } = useQuery({
    queryKey: ['runs', 'active'],
    queryFn: () => runsApi.list({ status: 'running' }),
    refetchOnWindowFocus: false,
  })

  const activeGoals = goalsData?.goals?.filter(g => g.status === 'active') || []
  const activeTasks = tasksData?.tasks?.filter(t => ['pending', 'running', 'in_progress'].includes(t.status)) || []
  const activeRuns = runsData?.runs || []

  const dirCount = fsData?.dirs?.length || 0
  const fileCount = fsData?.files?.length || 0
  const totalItems = dirCount + fileCount

  function handleFileSelect() {}

  return (
    <div className="w-80 border-l border-card-border bg-card-bg overflow-y-auto shrink-0">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-card-border sticky top-0 bg-card-bg z-10">
        <span className="text-xs font-semibold uppercase tracking-wider text-text-primary">Context</span>
        <button onClick={onClose} className="p-0.5 rounded hover:bg-gray-100 dark:hover:bg-gray-800 text-text-muted hover:text-text-primary transition-colors">
          <X className="w-3.5 h-3.5" />
        </button>
      </div>

      <div className="p-4 space-y-4 text-xs">
        {/* Active Goals */}
        {activeGoals.length > 0 && (
          <section>
            <h3 className="flex items-center gap-1.5 font-semibold text-text-primary mb-2 uppercase tracking-wider text-[10px]">
              <Target className="w-3 h-3 text-accent" /> Active Goals
            </h3>
            <div className="space-y-1.5">
              {activeGoals.slice(0, 3).map(goal => (
                <div key={goal.id} className="bg-gradient-to-r from-accent/5 to-transparent rounded-lg px-3 py-2 border border-accent/10">
                  <div className="font-medium text-text-primary text-[11px] truncate">{goal.title}</div>
                  {goal.description && (
                    <div className="text-text-muted text-[10px] mt-0.5 line-clamp-2">{goal.description}</div>
                  )}
                </div>
              ))}
              {activeGoals.length > 3 && (
                <div className="text-text-muted text-[10px] px-2">+{activeGoals.length - 3} more goals</div>
              )}
            </div>
          </section>
        )}

        {/* Active Tasks */}
        {activeTasks.length > 0 && (
          <section>
            <h3 className="flex items-center gap-1.5 font-semibold text-text-primary mb-2 uppercase tracking-wider text-[10px]">
              <ListTodo className="w-3 h-3 text-blue-500" /> Active Tasks
            </h3>
            <div className="space-y-1.5">
              {activeTasks.slice(0, 5).map(task => (
                <div key={task.id} className={cn(
                  "bg-gray-50 dark:bg-gray-800/50 rounded-lg px-3 py-2 border",
                  task.status === 'in_progress' ? "border-blue-200 dark:border-blue-800" : "border-gray-200 dark:border-gray-700"
                )}>
                  <div className="flex items-center gap-2">
                    <div className={cn(
                      "w-1.5 h-1.5 rounded-full shrink-0",
                      task.status === 'in_progress' ? "bg-blue-500" : "bg-gray-400"
                    )} />
                    <div className="font-medium text-text-primary text-[11px] truncate flex-1">{task.title}</div>
                  </div>
                  {task.status === 'in_progress' && (
                    <div className="text-[10px] text-blue-600 dark:text-blue-400 mt-1">In Progress</div>
                  )}
                </div>
              ))}
              {activeTasks.length > 5 && (
                <div className="text-text-muted text-[10px] px-2">+{activeTasks.length - 5} more tasks</div>
              )}
            </div>
          </section>
        )}

        {/* Running Background Runs */}
        {activeRuns.length > 0 && (
          <section>
            <h3 className="flex items-center gap-1.5 font-semibold text-text-primary mb-2 uppercase tracking-wider text-[10px]">
              <Activity className="w-3 h-3 text-green-500" /> Running ({activeRuns.length})
            </h3>
            <div className="space-y-1.5">
              {activeRuns.slice(0, 5).map(run => {
                const isExpanded = expandedRunId === run.run_id
                return (
                  <div key={run.run_id}>
                    <button
                      onClick={() => setExpandedRunId(isExpanded ? null : run.run_id)}
                      className="w-full text-left bg-green-50 dark:bg-green-950/20 rounded-lg px-3 py-2 border border-green-200 dark:border-green-800 hover:bg-green-100 dark:hover:bg-green-950/40 transition-colors"
                    >
                      <div className="flex items-center gap-2">
                        <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse shrink-0" />
                        <div className="font-medium text-text-primary text-[11px] truncate flex-1">
                          {run.objective || run.source_type || 'Run'} <span className="font-mono text-text-muted text-[10px]">#{run.run_id?.slice(0, 8)}</span>
                        </div>
                        <ChevronDown className={cn('w-3 h-3 text-text-muted shrink-0 transition-transform', isExpanded && 'rotate-180')} />
                      </div>
                      {(run.input?.task || run.task) && (
                        <div className="text-[10px] text-text-muted mt-1 truncate ml-4">{run.input?.task || run.task}</div>
                      )}
                    </button>
                    {isExpanded && (
                      <div className="mt-1 border border-gray-200 dark:border-gray-700 rounded-xl overflow-hidden bg-white dark:bg-gray-900 max-h-96 overflow-y-auto">
                        <RunDetail run={run} />
                      </div>
                    )}
                  </div>
                )
              })}
              {activeRuns.length > 5 && (
                <div className="text-text-muted text-[10px] px-2">+{activeRuns.length - 5} more runs</div>
              )}
            </div>
          </section>
        )}

        {/* Quick Stats */}
        {workspacePath && (
          <section className="bg-gradient-to-br from-accent/5 to-accent/10 rounded-xl p-3 border border-accent/20">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <FolderOpen className="w-4 h-4 text-accent" />
                <span className="font-semibold text-text-primary">Workspace</span>
              </div>
              {totalItems > 0 && (
                <span className="text-[10px] bg-accent/20 text-accent px-2 py-0.5 rounded-full font-medium">
                  {dirCount} dirs · {fileCount} files
                </span>
              )}
            </div>
            <div className="mt-2 text-text-secondary font-mono text-[10px] truncate">
              {workspacePath}
            </div>
          </section>
        )}

        {/* File Tree */}
        {workspacePath && (
          <section>
            <h3 className="flex items-center gap-1.5 font-semibold text-text-primary mb-2 uppercase tracking-wider text-[10px]">
              <FolderOpen className="w-3 h-3" /> Files
            </h3>
            <div className="bg-gray-50 dark:bg-gray-800/50 rounded-xl overflow-hidden">
              <FileTree path={workspacePath} onFileSelect={handleFileSelect} />
            </div>
          </section>
        )}

        {/* Session Info */}
        {sessionId && (
          <section>
            <h3 className="flex items-center gap-1.5 font-semibold text-text-primary mb-2 uppercase tracking-wider text-[10px]">
              <MessageSquare className="w-3 h-3" /> Session
            </h3>
            <div className="space-y-1.5 bg-gray-50 dark:bg-gray-800/50 rounded-xl p-3">
              <div>
                <span className="text-text-muted">ID: </span>
                <span className="text-text-primary font-mono break-all text-[10px]">{sessionId.slice(0, 8)}…</span>
              </div>
            </div>
          </section>
        )}

        {!workspacePath && !sessionId && activeGoals.length === 0 && activeTasks.length === 0 && activeRuns.length === 0 && (
          <div className="text-center py-8 text-text-muted">
            <Activity className="w-8 h-8 mx-auto mb-2 opacity-50" />
            <p className="text-xs">No active context</p>
            <p className="text-[10px] mt-1">Start a session or create goals to see context here</p>
          </div>
        )}
      </div>
    </div>
  )
}
