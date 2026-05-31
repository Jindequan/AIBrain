import { useState } from 'react'
import { ChevronDown, ChevronRight, Terminal, Loader, CheckCircle, XCircle, FileCode } from 'lucide-react'
import { cn } from '../../lib/utils'

const getIconForTool = (name) => {
  if (name.includes('bash') || name.includes('sh')) return Terminal
  if (name.includes('file')) return FileCode
  return Terminal
}

export function AggregatedToolCard({ toolName, calls, streaming }) {
  const [open, setOpen] = useState(false)
  const [expandedCalls, setExpandedCalls] = useState(new Set()) // Track which individual calls are expanded

  const isRunning = streaming && calls.some(c => c.status === 'running')
  const hasErrors = calls.some(c => c.status === 'error')
  const successCount = calls.filter(c => c.status === 'success').length
  const runningCount = calls.filter(c => c.status === 'running').length

  const toggleCall = (index) => {
    setExpandedCalls(prev => {
      const next = new Set(prev)
      if (next.has(index)) {
        next.delete(index)
      } else {
        next.add(index)
      }
      return next
    })
  }

  return (
    <div className={cn(
      'my-1 rounded-xl border text-xs overflow-hidden transition-colors',
      isRunning ? 'border-accent/30 bg-accent/[0.03]' :
      hasErrors ? 'border-red-200 bg-red-50/30' :
      'border-card-border bg-gray-50'
    )}>
      {/* Level 1: Aggregated tool header */}
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 w-full px-3 py-2 text-left text-text-secondary hover:text-text-primary hover:bg-gray-100/50 transition-colors"
      >
        {isRunning ? (
          <Loader className="w-3.5 h-3.5 text-accent animate-spin shrink-0" />
        ) : hasErrors ? (
          <XCircle className="w-3.5 h-3.5 text-red-500 shrink-0" />
        ) : (
          <CheckCircle className="w-3.5 h-3.5 text-emerald-500 shrink-0" />
        )}
        <span className="font-mono font-medium">{toolName}</span>
        <span className="text-text-muted">({calls.length} calls)</span>
        {isRunning && runningCount > 0 && (
          <span className="text-accent text-[10px] animate-pulse">{runningCount} running</span>
        )}
        {!isRunning && successCount === calls.length && successCount > 0 && (
          <span className="text-emerald-600 text-[10px]">{successCount} completed</span>
        )}
        {!isRunning && successCount < calls.length && successCount > 0 && (
          <span className="text-emerald-600 text-[10px]">{successCount}/{calls.length} completed</span>
        )}
        {open ? (
          <ChevronDown className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
        ) : (
          <ChevronRight className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
        )}
      </button>

      {/* Level 2: List of all calls */}
      {open && (
        <div className="border-t border-card-border divide-y divide-card-border">
          {calls.map((call, index) => {
            const Icon = getIconForTool(toolName)
            const isExpanded = expandedCalls.has(index)
            const callIsRunning = call.status === 'running' && streaming
            const callHasError = call.status === 'error'
            const callIsSuccess = call.status === 'success'

            // Format input for display
            const inputStr = typeof call.input === 'string'
              ? call.input
              : JSON.stringify(call.input, null, 2)

            // Truncate very long inputs for the summary view
            const displayInput = inputStr.length > 100
              ? inputStr.slice(0, 100) + '...'
              : inputStr

            return (
              <div key={call.id || index} className="px-3 py-2">
                {/* Level 2: Individual call header */}
                <button
                  onClick={() => toggleCall(index)}
                  className="flex items-start gap-2 w-full text-left group"
                >
                  <Icon className="w-3 h-3 mt-0.5 text-text-muted shrink-0" />
                  <span className="text-[10px] text-text-muted font-mono">#{index + 1}</span>
                  <pre className={cn(
                    'flex-1 text-xs font-mono truncate',
                    callHasError ? 'text-red-600' :
                    callIsSuccess ? 'text-emerald-700' :
                    'text-text-secondary'
                  )}>
                    {displayInput}
                  </pre>
                  {callIsRunning ? (
                    <Loader className="w-3 h-3 text-accent animate-spin shrink-0" />
                  ) : callHasError ? (
                    <XCircle className="w-3 h-3 text-red-500 shrink-0" />
                  ) : callIsSuccess ? (
                    <CheckCircle className="w-3 h-3 text-emerald-500 shrink-0" />
                  ) : (
                    <Terminal className="w-3 h-3 text-text-muted shrink-0" />
                  )}
                  {isExpanded ? (
                    <ChevronDown className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
                  ) : (
                    <ChevronRight className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
                  )}
                </button>

                {/* Level 3: Execution result */}
                {isExpanded && call.output !== null && !callIsRunning && (
                  <div className="ml-7 mt-2">
                    <div className={cn(
                      'text-[10px] font-semibold uppercase tracking-wide mb-1',
                      callHasError ? 'text-red-500' : 'text-emerald-600'
                    )}>
                      Result
                    </div>
                    <pre className={cn(
                      'overflow-x-auto whitespace-pre-wrap rounded-lg p-2 text-[11px] leading-relaxed max-h-[400px] overflow-y-auto',
                      callHasError ? 'text-red-600 bg-red-50' : 'text-text-secondary bg-white/60'
                    )}>
                      {typeof call.output === 'string' ? call.output : JSON.stringify(call.output, null, 2)}
                    </pre>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
