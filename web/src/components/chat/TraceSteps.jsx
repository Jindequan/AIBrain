import { memo } from 'react'
import { Terminal, ExternalLink } from 'lucide-react'

/**
 * L1 - Trace area for chat: minimal tool execution summary.
 *
 * Shows a single collapsed line: "N operations → view details"
 * Clicking navigates to the runs page for full execution trace.
 */
export const TraceSteps = memo(function TraceSteps({ steps, streaming, runId }) {
  if (!steps || steps.length === 0) return null

  const allTools = steps.flatMap(s => s.tools || [])
  const totalCalls = allTools.length
  const errorCalls = allTools.filter(t => t.status === 'error').length
  const runningCalls = allTools.filter(t => t.status === 'running').length

  if (totalCalls === 0) return null

  const runPath = runId ? `/runs/${runId}` : '/runs'

  return (
    <div className="flex items-center gap-2 py-1 px-2 rounded-md bg-gray-50 text-xs text-text-muted">
      <Terminal className="w-3.5 h-3.5 shrink-0" />

      {streaming && runningCalls > 0 ? (
        <span className="flex items-center gap-1">
          <span className="animate-pulse">Running {runningCalls} operation{runningCalls > 1 ? 's' : ''}...</span>
        </span>
      ) : (
        <span>
          {totalCalls} operation{totalCalls > 1 ? 's' : ''}
          {errorCalls > 0 && (
            <span className="text-amber-600 ml-1">
              ({errorCalls} failed)
            </span>
          )}
        </span>
      )}

      <a
        href={runPath}
        className="ml-auto flex items-center gap-1 text-text-muted hover:text-accent transition-colors"
      >
        <span>View details</span>
        <ExternalLink className="w-3 h-3" />
      </a>
    </div>
  )
})
