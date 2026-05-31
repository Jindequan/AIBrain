import { useState, memo } from 'react'
import { getToolIcon, getToolResourceInfo } from '../../lib/messageTransform'

const STATUS = {
  success: { icon: '✓', color: 'text-green-600', bg: 'bg-green-50 border-green-200' },
  error: { icon: '✗', color: 'text-red-600', bg: 'bg-red-50 border-red-200' },
  running: { icon: '⟳', color: 'text-amber-500', bg: 'bg-amber-50/40 border-amber-200' },
}

export const ToolCapsule = memo(function ToolCapsule({ tool }) {
  const [expanded, setExpanded] = useState(false)
  const icon = getToolIcon(tool.name)
  const resource = getToolResourceInfo(tool)
  const st = STATUS[tool.status] || STATUS.running
  const hasOutput = tool.output || tool.status === 'running'

  return (
    <div className={`border rounded-xl overflow-hidden transition-colors ${expanded ? 'border-blue-200 bg-blue-50/30' : 'border-card-border bg-card-bg/50'}`}>
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex items-center gap-2 w-full px-2 py-1 hover:bg-gray-50/80 transition-colors text-left"
      >
        <span className="shrink-0 text-xs leading-none">{icon}</span>
        <span className="text-xs font-mono text-text-secondary font-medium truncate shrink-0">{tool.name}</span>
        {resource && (
          <span className="text-xs text-text-muted truncate min-w-0 flex-1 hidden sm:block" title={resource}>
            {resource}
          </span>
        )}
        <span className={`ml-auto shrink-0 flex items-center gap-1 ${st.color}`}>
          {tool.status === 'running' ? (
            <span className="inline-block w-3 h-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
          ) : (
            <span className="text-xs font-bold">{st.icon}</span>
          )}
        </span>
      </button>

      {expanded && hasOutput && (
        <div className="border-t border-inherit max-h-[300px] overflow-y-auto">
          <pre className="p-2 text-[11px] text-text-secondary whitespace-pre-wrap font-mono leading-relaxed">
            {tool.status === 'running' ? 'Running…' : tool.output || ''}
          </pre>
        </div>
      )}
    </div>
  )
})
