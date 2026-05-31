import { useState, memo } from 'react'
import { ChevronDown, ChevronRight, Terminal, Loader, CheckCircle, XCircle, Eye, EyeOff, FileText, AlertTriangle, ShieldAlert, Clock, WifiOff, Ban } from 'lucide-react'
import { cn } from '../../lib/utils'

const LARGE_OUTPUT_THRESHOLD = 3000

const ERROR_CATEGORY_STYLES = {
  permission: { border: 'border-amber-300 bg-amber-50/30', icon: ShieldAlert, iconColor: 'text-amber-500', label: 'Permission denied' },
  invalid_params: { border: 'border-yellow-300 bg-yellow-50/30', icon: AlertTriangle, iconColor: 'text-yellow-500', label: 'Invalid parameters' },
  timeout: { border: 'border-gray-300 bg-gray-50/30', icon: Clock, iconColor: 'text-gray-500', label: 'Timed out' },
  external_service: { border: 'border-purple-300 bg-purple-50/30', icon: WifiOff, iconColor: 'text-purple-500', label: 'External service error' },
  unavailable: { border: 'border-gray-300 bg-gray-50/30', icon: Ban, iconColor: 'text-gray-400', label: 'Tool unavailable' },
  execution: { border: 'border-red-200 bg-red-50/30', icon: XCircle, iconColor: 'text-red-500', label: 'Execution failed' },
}

export const ToolCallCard = memo(function ToolCallCard({
  name, input, output, status, streaming,
  error_category: errorCategory, file_path: filePath, truncated, byte_size: byteSize
}) {
  const [open, setOpen] = useState(false)
  const [showFullOutput, setShowFullOutput] = useState(false)
  const isRunning = status === 'running' && streaming
  const isSuccess = status === 'success'
  const isError = status === 'error'

  const catStyle = isError && errorCategory ? ERROR_CATEGORY_STYLES[errorCategory] : null
  const ErrorIcon = catStyle?.icon || XCircle

  const outputStr = typeof output === 'string' ? output : JSON.stringify(output, null, 2)
  const isLargeOutput = outputStr && outputStr.length > LARGE_OUTPUT_THRESHOLD
  const truncatedOutput = isLargeOutput && !showFullOutput
    ? outputStr.slice(0, LARGE_OUTPUT_THRESHOLD) + '\n\n... (truncated, click to show more)'
    : outputStr

  return (
    <div className={cn(
      'my-1 rounded-xl border text-xs overflow-hidden transition-colors',
      isRunning ? 'border-accent/30 bg-accent/[0.03]' :
      catStyle ? catStyle.border :
      isError ? 'border-red-200 bg-red-50/30' :
      'border-card-border bg-gray-50'
    )}>
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 w-full px-3 py-2 text-left text-text-secondary hover:text-text-primary hover:bg-gray-100/50 transition-colors"
      >
        {isRunning ? (
          <Loader className="w-3.5 h-3.5 text-accent animate-spin shrink-0" />
        ) : isSuccess ? (
          <CheckCircle className="w-3.5 h-3.5 text-emerald-500 shrink-0" />
        ) : isError ? (
          <ErrorIcon className={cn('w-3.5 h-3.5 shrink-0', catStyle?.iconColor || 'text-red-500')} />
        ) : (
          <Terminal className="w-3.5 h-3.5 text-accent shrink-0" />
        )}
        <span className="font-mono font-medium">{name}</span>
        {isError && catStyle && (
          <span className={cn('text-[10px]', catStyle.iconColor)}>{catStyle.label}</span>
        )}
        {isRunning && <span className="text-accent text-[10px] animate-pulse">running…</span>}
        {open ? (
          <ChevronDown className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
        ) : (
          <ChevronRight className="w-3 h-3 ml-auto shrink-0 text-text-muted" />
        )}
      </button>
      {open && (
        <div className="border-t border-card-border divide-y divide-card-border">
          {input && (
            <div className="px-3 py-2">
              <div className="text-[10px] font-semibold text-text-muted uppercase tracking-wide mb-1">Input</div>
              <pre className="text-text-secondary overflow-x-auto whitespace-pre-wrap bg-white/60 rounded-lg p-2 text-[11px] leading-relaxed">
                {typeof input === 'string' ? input : JSON.stringify(input, null, 2)}
              </pre>
            </div>
          )}
          {output !== null && !isRunning && (
            <div className="px-3 py-2">
              <div className="flex items-center justify-between mb-1">
                <div className={cn(
                  'text-[10px] font-semibold uppercase tracking-wide',
                  isError ? 'text-red-500' : 'text-emerald-600'
                )}>
                  Result
                  {(isLargeOutput || truncated) && byteSize && (
                    <span className="ml-2 text-text-muted font-normal normal-case">
                      ({(byteSize / 1024).toFixed(1)} KB{truncated ? ', full output saved to file' : ''})
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  {filePath && (
                    <a
                      href={`/api/v1/files/${encodeURIComponent(filePath)}`}
                      className="text-[10px] font-medium text-accent hover:text-accent/80 flex items-center gap-1"
                      target="_blank"
                      rel="noopener"
                    >
                      <FileText className="w-3 h-3" />
                      Full file
                    </a>
                  )}
                  {isLargeOutput && (
                    <button
                      onClick={() => setShowFullOutput(!showFullOutput)}
                      className="text-[10px] font-medium text-accent hover:text-accent/80 flex items-center gap-1"
                    >
                      {showFullOutput ? (
                        <>
                          <EyeOff className="w-3 h-3" />
                          Show less
                        </>
                      ) : (
                        <>
                          <Eye className="w-3 h-3" />
                          Show all
                        </>
                      )}
                    </button>
                  )}
                </div>
              </div>
              <pre className={cn(
                'overflow-x-auto whitespace-pre-wrap rounded-lg p-2 text-[11px] leading-relaxed',
                isError ? 'text-red-600 bg-red-50' : 'text-text-secondary bg-white/60'
              )}>
                {truncatedOutput}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  )
})
