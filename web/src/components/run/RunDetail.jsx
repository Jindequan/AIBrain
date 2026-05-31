import { useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  XCircle, Clock, CheckCircle, AlertCircle, RotateCw,
  ChevronRight, CornerDownRight, GitBranch, FileText, Folder,
  Maximize2, Minimize2, ArrowLeft, Shield, Eye, Wrench,
  Layers, BookOpen, AlertTriangle
} from 'lucide-react'
import { runsApi } from '../../api/runs.api'
import { fsApi } from '../../api/filesystem.api'
import { buildApiUrl } from '../../api/client'
import { mutationError } from '../../store/toastStore'
import { cn } from '../../lib/utils'
import { useRunEvents } from '../../hooks/useRunEvents'
import { Badge } from '../ui/design'

// ═══════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════

export const STATUS_CONFIG = {
  pending: { icon: Clock, bg: 'bg-amber-500/10', text: 'text-amber-600', label: 'Pending' },
  running: { icon: RotateCw, bg: 'bg-blue-500/10', text: 'text-blue-600', label: 'Running' },
  waiting_approval: { icon: Clock, bg: 'bg-amber-500/10', text: 'text-amber-600', label: 'Awaiting Approval' },
  waiting_assistant: { icon: Clock, bg: 'bg-purple-500/10', text: 'text-purple-600', label: 'Awaiting Assistant' },
  completed: { icon: CheckCircle, bg: 'bg-green-500/10', text: 'text-green-600', label: 'Completed' },
  failed: { icon: AlertCircle, bg: 'bg-red-500/10', text: 'text-red-600', label: 'Failed' },
  cancelled: { icon: XCircle, bg: 'bg-gray-500/10', text: 'text-text-muted', label: 'Cancelled' },
}

const PREVIEW_EXTS = ['md', 'json', 'pdf', 'txt', 'yaml', 'yml', 'toml', 'ex', 'exs']

// ═══════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════

export function formatTime(iso) {
  if (!iso) return ''
  return new Date(iso).toLocaleString()
}

export function sourceTypeLabel(type) {
  if (type === 'session' || type === 'chat') return 'Chat'
  if (type === 'task') return 'Task'
  if (type === 'manual') return 'Manual'
  return type || 'Run'
}

export function formatShortTime(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const now = new Date()
  const diff = now - d
  if (diff < 60000) return 'just now'
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
  return d.toLocaleDateString()
}

// ═══════════════════════════════════════════════════════════
// Sub-components
// ═══════════════════════════════════════════════════════════

function SimpleMarkdown({ content }) {
  const html = useMemo(() => {
    if (!content) return ''
    return content
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/^######\s+(.+)$/gm, '<h6 class="text-xs font-bold mt-2 mb-1">$1</h6>')
      .replace(/^#####\s+(.+)$/gm, '<h5 class="text-sm font-bold mt-2 mb-1">$1</h5>')
      .replace(/^####\s+(.+)$/gm, '<h4 class="text-sm font-bold mt-2 mb-1">$1</h4>')
      .replace(/^###\s+(.+)$/gm, '<h3 class="text-sm font-bold mt-3 mb-1">$1</h3>')
      .replace(/^##\s+(.+)$/gm, '<h2 class="text-base font-bold mt-4 mb-1">$1</h2>')
      .replace(/^#\s+(.+)$/gm, '<h1 class="text-lg font-bold mt-4 mb-2">$1</h1>')
      .replace(/```(\w*)\n([\s\S]*?)```/g, '<pre class="bg-gray-100 dark:bg-gray-800 p-3 rounded text-xs overflow-x-auto my-2"><code>$2</code></pre>')
      .replace(/`([^`]+)`/g, '<code class="bg-gray-100 dark:bg-gray-800 px-1 rounded text-[11px] font-mono text-red-500">$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\*([^*]+)\*/g, '<em>$1</em>')
      .replace(/^- (.+)$/gm, '<li class="ml-4 list-disc text-sm">$1</li>')
      .replace(/^(\d+)\. (.+)$/gm, '<li class="ml-4 list-decimal text-sm">$2</li>')
      .replace(/---/g, '<hr class="my-3 border-gray-200 dark:border-gray-700" />')
      .replace(/\n\n/g, '<br/><br/>')
  }, [content])

  return <div className="markdown-body" dangerouslySetInnerHTML={{ __html: html }} />
}

function SyntaxHighlightedJson({ content }) {
  const html = useMemo(() => {
    if (!content) return ''
    let raw
    try { raw = JSON.stringify(JSON.parse(content), null, 2) } catch { raw = content }
    return raw
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"([^"]+)":/g, '<span class="text-blue-600">"$1"</span>:')
      .replace(/"([^"]+)"(,?)$/gm, '<span class="text-green-600">"$1"</span>$2')
      .replace(/\b(true|false)\b/g, '<span class="text-purple-600">$1</span>')
      .replace(/\b(\d+\.?\d*)\b/g, '<span class="text-amber-600">$1</span>')
      .replace(/\bnull\b/g, '<span class="text-gray-400">null</span>')
  }, [content])

  return <span dangerouslySetInnerHTML={{ __html: html }} />
}

function FullFilePreview({ path, onClose }) {
  const ext = path?.split('.').pop()?.toLowerCase()
  const filename = path?.split('/').pop() || ''
  const isPdf = ext === 'pdf'

  const { data: content, isLoading, error } = useQuery({
    queryKey: ['file-read', path],
    queryFn: () => fsApi.read(path),
    enabled: !!path && !isPdf,
    staleTime: 60000,
  })

  return (
    <div className="h-full flex flex-col">
      <div className="flex items-center justify-between px-4 py-2 bg-gray-50 dark:bg-gray-800/50 border-b border-gray-100 dark:border-gray-800 shrink-0">
        <span className="text-xs font-mono text-text-primary truncate">{filename}</span>
        <button onClick={onClose}
          className="text-[10px] text-text-muted hover:text-text-primary px-2 py-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700">
          Close
        </button>
      </div>
      <div className="flex-1 overflow-auto bg-white dark:bg-gray-800/30">
        {isPdf ? (
          <iframe src={buildApiUrl(`/api/v1/file/read?path=${encodeURIComponent(path)}`)}
            className="w-full h-full" title={filename} />
        ) : isLoading ? (
          <div className="flex items-center justify-center h-full text-xs text-text-muted">Loading...</div>
        ) : error ? (
          <div className="flex items-center justify-center h-full text-xs text-red-500">
            {error instanceof Error ? error.message : 'Failed to read file'}
          </div>
        ) : content != null ? (
          ext === 'md' ? (
            <div className="px-6 py-4 text-sm leading-relaxed max-w-none">
              <SimpleMarkdown content={content} />
            </div>
          ) : ext === 'json' ? (
            <pre className="px-4 py-3 text-xs overflow-auto"><SyntaxHighlightedJson content={content} /></pre>
          ) : (
            <pre className="px-4 py-3 text-xs overflow-auto whitespace-pre-wrap">{content}</pre>
          )
        ) : null}
      </div>
    </div>
  )
}

function DeliverablePreview({ del, onPreview }) {
  const ext = del.path?.split('.').pop()?.toLowerCase()
  const hasPreview = ext && PREVIEW_EXTS.includes(ext)

  if (del.type === 'artifact') {
    return (
      <div className="flex items-start gap-2.5 text-xs bg-green-500/5 border border-green-500/20 rounded-xl px-3 py-2.5">
        <FileText className="w-4 h-4 text-green-600 shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <div className="font-medium text-text-primary">{del.title || 'Artifact'}</div>
          {del.description && <p className="text-text-muted mt-0.5 text-[11px]">{del.description}</p>}
          <span className="text-[10px] text-green-600 uppercase mt-1 inline-block">Artifact</span>
        </div>
      </div>
    )
  }

  if (del.type === 'file' || del.path) {
    return (
      <div className="flex items-start gap-2.5 text-xs bg-green-500/5 border border-green-500/20 rounded-xl px-3 py-2.5">
        <FileText className="w-4 h-4 text-green-600 shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <div className="font-medium text-text-primary font-mono text-[11px] break-all">{del.path}</div>
          {del.description && <p className="text-text-muted mt-0.5">{del.description}</p>}
          <span className="text-[10px] text-green-600 uppercase mt-1 inline-block">File</span>
        </div>
        {hasPreview && (
          <button onClick={() => onPreview(del.path)}
            className="text-accent hover:underline text-[10px] shrink-0 mt-0.5">
            Preview
          </button>
        )}
      </div>
    )
  }

  if (del.type === 'project') {
    return (
      <div className="flex items-start gap-2.5 text-xs bg-green-500/5 border border-green-500/20 rounded-xl px-3 py-2.5">
        <Folder className="w-4 h-4 text-green-600 shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <div className="font-medium text-text-primary font-mono text-[11px] break-all">{del.path}</div>
          {del.description && <p className="text-text-muted mt-0.5">{del.description}</p>}
          <span className="text-[10px] text-green-600 uppercase mt-1 inline-block">Project</span>
        </div>
      </div>
    )
  }

  return null
}

function MetadataSection({ icon: Icon, title, children, defaultOpen = false }) {
  const [open, setOpen] = useState(defaultOpen)
  return (
    <div className="border border-gray-200 dark:border-gray-700 rounded-xl overflow-hidden">
      <button onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-3 py-2 text-xs font-semibold text-text-muted hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors">
        <Icon className="w-3.5 h-3.5 shrink-0" />
        <span className="flex-1 text-left">{title}</span>
        <ChevronRight className={cn('w-3 h-3 transition-transform', open && 'rotate-90')} />
      </button>
      {open && <div className="px-3 pb-3 text-xs">{children}</div>}
    </div>
  )
}

function KeyValuePairs({ data }) {
  if (!data || typeof data !== 'object') return null
  return (
    <div className="space-y-1">
      {Object.entries(data).map(([k, v]) => {
        if (typeof v === 'object' && v !== null) return null
        return (
          <div key={k} className="flex gap-2">
            <span className="text-text-muted font-mono min-w-[120px]">{k}</span>
            <span className={cn(
              typeof v === 'boolean' ? (v ? 'text-green-600' : 'text-red-500') :
              typeof v === 'number' ? 'text-blue-600' :
              'text-text-primary'
            )}>{String(v)}</span>
          </div>
        )
      })}
    </div>
  )
}

function CheckBadge({ status }) {
  const colors = {
    available: 'bg-green-500/10 text-green-600',
    degraded: 'bg-amber-500/10 text-amber-600',
    unavailable: 'bg-red-500/10 text-red-500',
    unsupported: 'bg-gray-500/10 text-gray-400',
  }
  return <span className={cn('px-1.5 py-0.5 rounded text-[10px] font-medium', colors[status] || 'bg-gray-100 text-gray-500')}>{status}</span>
}

// ═══════════════════════════════════════════════════════════
// RunDetail — main export
// ═══════════════════════════════════════════════════════════

export default function RunDetail({ run, onClose, fullscreen, onToggleFullscreen }) {
  const queryClient = useQueryClient()
  const [showChain, setShowChain] = useState(true)
  const [previewFile, setPreviewFile] = useState(null)

  const runId = run?.run_id
  const runStatus = run?.status || 'pending'
  const cfg = STATUS_CONFIG[runStatus] || STATUS_CONFIG.pending
  const Icon = cfg.icon
  const isActive = runStatus === 'running' || runStatus === 'pending'

  const cancelMutation = useMutation({
    mutationFn: (id) => runsApi.cancel(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['runs'] }),
    onError: mutationError('Cancel run failed'),
  })

  const { data: stepsData } = useQuery({
    queryKey: ['run-steps', runId],
    queryFn: () => runsApi.steps(runId),
    enabled: !!runId,
  })

  const { data: evidenceData } = useQuery({
    queryKey: ['run-evidence', runId],
    queryFn: () => runsApi.evidence(runId),
    enabled: !!runId,
  })

  const { data: verificationData } = useQuery({
    queryKey: ['run-verification', runId],
    queryFn: () => runsApi.verification(runId),
    enabled: !!runId,
  })

  const steps = stepsData?.steps || []
  const evidence = evidenceData?.evidence || []
  const verification = verificationData?.verification

  // Real-time tool events via WebSocket (active runs only)
  const { steps: liveSteps, runningCount, failedCount: liveFailed } = useRunEvents(
    isActive ? runId : null
  )

  if (!run) return null

  const meta = run.metadata || {}
  const understanding = meta.request_understanding
  const capabilityCheck = meta.capability_check
  const contextPlan = meta.context_plan
  const completionRecord = meta.completion_record
  const approvalId = meta.approval_id || meta.interaction_id

  const hasDeliverables = run.deliverables && run.deliverables.length > 0
  const hasChildren = run.child_runs && run.child_runs.length > 0

  if (previewFile) {
    return (
      <div className="flex-1 flex flex-col">
        <div className="flex items-center gap-2 px-4 py-2 border-b border-gray-100 dark:border-gray-800 bg-gray-50 dark:bg-gray-800/50 shrink-0">
          <button onClick={() => setPreviewFile(null)}
            className="flex items-center gap-1 text-xs text-accent hover:underline shrink-0">
            <ArrowLeft className="w-3.5 h-3.5" /> Back to detail
          </button>
          <span className="text-xs font-mono text-text-primary truncate">{previewFile.split('/').pop()}</span>
          <span className="text-[10px] text-text-muted truncate hidden sm:inline">{previewFile}</span>
        </div>
        <div className="flex-1 min-h-0">
          <FullFilePreview path={previewFile} onClose={() => setPreviewFile(null)} />
        </div>
      </div>
    )
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-start gap-3 px-6 pt-5 pb-4 border-b border-gray-100 dark:border-gray-800 shrink-0 bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
        {fullscreen && (
          <button onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-text-muted shrink-0 mt-1" title="Back to list">
            <ArrowLeft className="w-4 h-4" />
          </button>
        )}
        <div className={cn('p-2.5 rounded-xl', cfg.bg, cfg.text)}>
          <Icon className={cn('w-5 h-5', run.status === 'running' && 'animate-spin')} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h2 className="text-base font-bold text-text-primary">{run.objective || sourceTypeLabel(run.source_type)}</h2>
            <Badge size="sm" variant={
              run.status === 'completed' ? 'success' :
              run.status === 'running' ? 'info' :
              run.status === 'failed' ? 'danger' :
              run.status === 'cancelled' ? 'default' :
              'warning'
            }>{cfg.label}</Badge>
            {run.parent && <Badge size="sm" variant="info"><span className="flex items-center gap-0.5"><GitBranch className="w-3 h-3" /> delegated</span></Badge>}
          </div>
          <div className="flex items-center gap-3 mt-1 text-[11px] text-text-muted">
            <span>{sourceTypeLabel(run.source_type)}</span>
            {run.started_at && <span>{formatTime(run.started_at)}</span>}
            {run.completed_at && <span>&rarr; {formatTime(run.completed_at)}</span>}
            <span className="font-mono">#{run.run_id?.slice(0, 8)}</span>
            {run.model && <span className="text-accent">{run.model}</span>}
          </div>
        </div>
        <div className="flex gap-1.5 shrink-0">
          {onToggleFullscreen && (
            <button onClick={onToggleFullscreen}
              className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-text-muted" title={fullscreen ? 'Split view' : 'Full screen'}>
              {fullscreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
            </button>
          )}
          {onClose && (
            <button onClick={onClose}
              className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-text-muted" title="Close">
              <XCircle className="w-3.5 h-3.5" />
            </button>
          )}
          {isActive && (
            <button onClick={() => cancelMutation.mutate(run.run_id)}
              className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-red-500/10 text-red-400 hover:bg-red-500/20 text-xs" title="Cancel">
              <XCircle className="w-3.5 h-3.5" /> Cancel
            </button>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto space-y-3 px-6 py-4">
        {run.parent && (
          <div className="flex items-center gap-2 text-xs text-text-muted bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2">
            <CornerDownRight className="w-3.5 h-3.5 shrink-0" />
            <span>Triggered by <span className="font-medium text-text-secondary">Run</span></span>
            <span className="font-mono">#{run.parent.run_id?.slice(0, 8)}</span>
          </div>
        )}

        {run.error && (
          <div>
            <h3 className="text-xs font-semibold text-red-500 mb-1.5">Error</h3>
            <div className="text-sm text-red-600 bg-red-50 dark:bg-red-950/30 rounded-xl px-3 py-2">{run.error}</div>
          </div>
        )}

        {run.status === 'waiting_approval' && (
          <div className="flex items-start gap-3 rounded-xl border border-amber-400/30 bg-amber-500/10 px-3 py-3">
            <Shield className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-text-primary">Waiting for approval</div>
              <p className="text-xs text-text-muted mt-0.5">{meta.reason || capabilityCheck?.reason || 'This run is paused until you approve or deny it.'}</p>
              <Link
                to={approvalId ? `/approvals?interaction_id=${encodeURIComponent(approvalId)}` : '/approvals'}
                className="inline-flex items-center gap-1 mt-2 text-xs font-medium text-amber-700 hover:underline"
              >
                Open approval
                <ChevronRight className="w-3 h-3" />
              </Link>
            </div>
          </div>
        )}

        {/* Request Understanding */}
        {understanding && (
          <MetadataSection icon={Eye} title={`Understanding: ${understanding.intent || understanding["intent"] || "unknown"}`} defaultOpen>
            <KeyValuePairs data={typeof understanding === 'object' ? Object.fromEntries(
              Object.entries(understanding).map(([k, v]) => [k, Array.isArray(v) ? v.join(', ') || '(none)' : v])
            ) : {}} />
          </MetadataSection>
        )}

        {/* Capability Check */}
        {capabilityCheck && (
          <MetadataSection icon={Shield} title={`Capability: ${capabilityCheck.status || capabilityCheck["status"] || "?"}`} defaultOpen={capabilityCheck.status === 'blocked'}>
            <div className="space-y-1.5">
              <div className="text-text-muted">{capabilityCheck.reason || capabilityCheck["reason"]}</div>
              {(capabilityCheck.checks || capabilityCheck["checks"]) && (
                <div className="grid grid-cols-2 gap-1 mt-1">
                  {Object.entries(capabilityCheck.checks || capabilityCheck["checks"] || {}).map(([cap, status]) => (
                    <div key={cap} className="flex items-center justify-between px-2 py-1 bg-gray-50 dark:bg-gray-800/30 rounded-lg">
                      <span className="font-mono text-[10px] text-text-secondary">{cap}</span>
                      <CheckBadge status={status} />
                    </div>
                  ))}
                </div>
              )}
            </div>
          </MetadataSection>
        )}

        {/* Context Plan */}
        {contextPlan && (
          <MetadataSection icon={Layers} title="Context Plan" defaultOpen={false}>
            <div className="grid grid-cols-3 gap-1">
              {Object.entries(contextPlan).map(([k, v]) => (
                <div key={k} className={cn(
                  'flex items-center gap-1.5 px-2 py-1 rounded-lg text-[10px]',
                  v ? 'bg-green-500/5 text-green-600' : 'bg-gray-50 dark:bg-gray-800/30 text-gray-400'
                )}>
                  <span className={cn('w-1.5 h-1.5 rounded-full', v ? 'bg-green-500' : 'bg-gray-300')} />
                  <span className="truncate">{k.replace('load_', '')}</span>
                </div>
              ))}
            </div>
          </MetadataSection>
        )}

        {/* Real-time tool progress (active runs) */}
        {isActive && liveSteps.length > 0 && (
          <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-blue-500/5 border border-blue-500/20">
            <RotateCw className={cn('w-4 h-4 text-blue-500', runningCount > 0 && 'animate-spin')} />
            <div className="flex-1 text-xs">
              <span className="text-blue-600 font-medium">
                {runningCount > 0 ? `${runningCount} running` : 'Processing...'}
              </span>
              {liveSteps.length > 0 && (
                <span className="text-text-muted ml-2">
                  {liveSteps.filter(s => s.status === 'success').length}/{liveSteps.length} tools
                </span>
              )}
            </div>
            {liveFailed > 0 && (
              <Badge size="sm" variant="danger">{liveFailed} failed</Badge>
            )}
          </div>
        )}

        {/* Execution Steps */}
        {(steps.length > 0 || liveSteps.length > 0) && (
          <MetadataSection icon={Wrench} title={`Steps (${steps.length || liveSteps.length})`} defaultOpen>
            <div className="space-y-1">
              {steps.map((step, i) => {
                const stepCfg = STATUS_CONFIG[step.status] || STATUS_CONFIG.pending
                const StepIcon = stepCfg.icon
                return (
                  <div key={i} className="flex items-center gap-2 px-2 py-1.5 bg-gray-50 dark:bg-gray-800/30 rounded-lg">
                    <div className={cn('p-1 rounded', stepCfg.bg, stepCfg.text)}>
                      <StepIcon className={cn('w-3 h-3', step.status === 'running' && 'animate-spin')} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5">
                        <span className="text-[10px] font-mono text-text-muted">{step.phase}</span>
                        <span className="text-text-primary font-medium">{step.title}</span>
                      </div>
                      {step.summary && <div className="text-text-muted truncate">{step.summary}</div>}
                    </div>
                    <Badge size="sm" variant={step.status === 'completed' ? 'success' : step.status === 'failed' ? 'danger' : 'warning'}>
                      {step.status}
                    </Badge>
                  </div>
                )
              })}
            </div>
          </MetadataSection>
        )}

        {hasDeliverables && (
          <div>
            <h3 className="text-xs font-semibold text-text-muted mb-1.5">Deliverables ({run.deliverables.length})</h3>
            <div className="space-y-2">
              {run.deliverables.map((del, i) => (
                <DeliverablePreview key={i} del={del} onPreview={setPreviewFile} />
              ))}
            </div>
          </div>
        )}

        {run.output_summary && !hasDeliverables && (
          <div>
            <h3 className="text-xs font-semibold text-text-muted mb-1.5">Output</h3>
            {run.output_summary.includes('#') || run.output_summary.includes('```') || run.output_summary.includes('**') ? (
              <div className="text-sm text-text-primary bg-gray-50 dark:bg-gray-800/30 rounded-xl px-3 py-2 leading-relaxed">
                <SimpleMarkdown content={run.output_summary} />
              </div>
            ) : (
              <div className="text-sm text-text-primary bg-gray-50 dark:bg-gray-800/30 rounded-xl px-3 py-2 whitespace-pre-wrap leading-relaxed">
                {run.output_summary}
              </div>
            )}
          </div>
        )}

        {/* Evidence */}
        {evidence.length > 0 && (
          <MetadataSection icon={BookOpen} title={`Evidence (${evidence.length})`} defaultOpen={false}>
            <div className="space-y-1">
              {evidence.map((item) => (
                <div key={item.id} className="flex items-start gap-2 px-2 py-1.5 bg-gray-50 dark:bg-gray-800/30 rounded-lg">
                  <div className="flex-1 min-w-0">
                    <div className="text-text-primary">{item.claim}</div>
                    <div className="flex items-center gap-2 mt-0.5 text-text-muted">
                      <span>{item.source_type}</span>
                      {item.tool_name && <span>&middot; {item.tool_name}</span>}
                      <span>&middot; {Math.round(item.confidence * 100)}%</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </MetadataSection>
        )}

        {/* Verification */}
        {verification && (
          <MetadataSection icon={AlertTriangle} title={`Verification: ${verification.status || 'done'}`} defaultOpen={verification.status === 'warning'}>
            <div className="space-y-1.5">
              {verification.warnings?.length > 0 && (
                <div>
                  <span className="font-medium text-amber-600">Warnings:</span>
                  <ul className="mt-1 space-y-0.5">{verification.warnings.map((w, i) => <li key={i} className="text-amber-600">- {w}</li>)}</ul>
                </div>
              )}
              {verification.failures?.length > 0 && (
                <div>
                  <span className="font-medium text-red-500">Failures:</span>
                  <ul className="mt-1 space-y-0.5">{verification.failures.map((f, i) => <li key={i} className="text-red-500">- {f}</li>)}</ul>
                </div>
              )}
              {verification.unknowns?.length > 0 && (
                <div>
                  <span className="font-medium text-blue-500">Unknowns:</span>
                  <ul className="mt-1 space-y-0.5">{verification.unknowns.map((u, i) => <li key={i} className="text-blue-500">- {u}</li>)}</ul>
                </div>
              )}
            </div>
          </MetadataSection>
        )}

        {/* Completion Record */}
        {completionRecord && (
          <MetadataSection icon={FileText} title="Completion Record" defaultOpen={run.status === 'failed'}>
            <div className="space-y-1.5">
              <KeyValuePairs data={{
                status: completionRecord.status,
                final_answer: completionRecord.final_answer,
                next_step: completionRecord.next_step,
              }} />
              {completionRecord.not_done?.length > 0 && (
                <div className="mt-1">
                  <span className="font-medium text-red-500">Not done:</span>
                  <ul className="mt-0.5 space-y-0.5">{completionRecord.not_done.map((n, i) => <li key={i} className="text-red-500">- {n}</li>)}</ul>
                </div>
              )}
              {completionRecord.what_changed?.length > 0 && (
                <div className="mt-1">
                  <span className="font-medium text-green-600">Changed:</span>
                  <ul className="mt-0.5 space-y-0.5">{completionRecord.what_changed.map((c, i) => <li key={i} className="text-green-600">- {c}</li>)}</ul>
                </div>
              )}
            </div>
          </MetadataSection>
        )}

        {hasChildren && (
          <div>
            <button onClick={() => setShowChain(!showChain)}
              className="flex items-center gap-1.5 text-xs font-semibold text-text-muted mb-1.5">
              <GitBranch className="w-3.5 h-3.5" />
              Execution Chain ({run.child_runs.length})
              <ChevronRight className={cn('w-3 h-3 transition-transform', showChain && 'rotate-90')} />
            </button>
            {showChain && (
              <div className="space-y-1.5 ml-1 pl-3 border-l-2 border-gray-200 dark:border-gray-700">
                {run.child_runs.map((child) => {
                  const c = STATUS_CONFIG[child.status] || STATUS_CONFIG.pending
                  const Ci = c.icon
                  return (
                    <div key={child.run_id}
                      className="flex items-center gap-2.5 text-xs bg-gray-50 dark:bg-gray-800/30 rounded-xl px-3 py-2">
                      <div className={cn('p-1 rounded', c.bg, c.text)}>
                        <Ci className="w-3 h-3" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="font-medium text-text-primary">{sourceTypeLabel(child.source_type)}</div>
                        <div className="text-text-muted">{c.label} &middot; {formatShortTime(child.started_at)}</div>
                      </div>
                      <span className="font-mono text-[10px] text-text-muted">#{child.run_id?.slice(0, 8)}</span>
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        )}
      </div>

      <div className="shrink-0 px-6 py-2 border-t border-gray-100 dark:border-gray-800 bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
        <div className="flex items-center justify-between text-[10px] text-text-muted">
          <span className="font-mono">Run ID: {run.run_id}</span>
          <span>{sourceTypeLabel(run.source_type)} &middot; {cfg.label}</span>
        </div>
      </div>
    </div>
  )
}
