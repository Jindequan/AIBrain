import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Shield, Check, X, ChevronRight, User, Bot, AlertTriangle } from 'lucide-react'
import { interactionsApi } from '../api/interactions.api'
import { mutationError } from '../store/toastStore'
import { cn } from '../lib/utils'
import { SectionHeader, Badge, Loading } from '../components/ui/design'

const STATUSES = ['all', 'pending', 'proxy_running', 'need_manual', 'resolved', 'escalated', 'expired']

const TYPE_ICONS = {
  confirm: Shield,
  approval: Shield,
  select: ChevronRight,
  text_input: ChevronRight,
  form: ChevronRight,
  shell_exec: AlertTriangle,
}

const STATUS_COLORS = {
  pending: 'warning',
  proxy_running: 'info',
  need_manual: 'error',
  resolved: 'success',
  escalated: 'warning',
  expired: 'default',
  cancelled: 'default',
}

import { formatRelative, formatAbsolute } from '../lib/time'

export default function ApprovalsPage() {
  const queryClient = useQueryClient()
  const [searchParams] = useSearchParams()
  const [statusFilter, setStatusFilter] = useState('all')
  const [expandedId, setExpandedId] = useState(null)
  const focusedInteractionId = searchParams.get('interaction_id')

  const { data, isLoading } = useQuery({
    queryKey: ['interactions'],
    queryFn: () => interactionsApi.list(),
    refetchInterval: 10000,
  })

  const resolveMutation = useMutation({
    mutationFn: ({ id, decision }) =>
      interactionsApi.resolve(id, { result: { decision } }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['interactions'] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-interactions'] })
      queryClient.invalidateQueries({ queryKey: ['runs'] })
      setExpandedId(null)
    },
    onError: mutationError('Resolve failed'),
  })

  const stopProxyMutation = useMutation({
    mutationFn: (id) => interactionsApi.stopProxy(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['interactions'] }),
    onError: mutationError('Stop proxy failed'),
  })

  const interactions = (data?.interactions || [])
    .filter((i) => statusFilter === 'all' || i.status === statusFilter)
    .sort((a, b) => new Date(b.inserted_at) - new Date(a.inserted_at))

  const allInteractions = data?.interactions || []
  const pendingCount = allInteractions.filter((i) => i.status === 'pending' || i.status === 'need_manual').length
  const proxyCount = allInteractions.filter((i) => i.status === 'proxy_running').length
  const resolvedCount = allInteractions.filter((i) => i.status === 'resolved').length
  const escalatedCount = allInteractions.filter((i) => i.status === 'escalated').length

  useEffect(() => {
    if (focusedInteractionId) setExpandedId(focusedInteractionId)
  }, [focusedInteractionId])

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-5xl mx-auto px-6 py-8">
        <div className="flex items-center justify-between">
          <SectionHeader title="Approvals" description="Authorization requests and decisions" icon={Shield} />
        </div>

        <div className="grid grid-cols-4 gap-3 mt-6 mb-4">
          <StatBadge label="Action needed" value={pendingCount} color="text-amber-600" bg="bg-amber-500/10" />
          <StatBadge label="Proxy running" value={proxyCount} color="text-blue-600" bg="bg-blue-500/10" />
          <StatBadge label="Resolved" value={resolvedCount} color="text-green-600" bg="bg-green-500/10" />
          <StatBadge label="Escalated" value={escalatedCount} color="text-orange-600" bg="bg-orange-500/10" />
        </div>

        <div className="flex items-center gap-2 mb-4">
          {STATUSES.map((s) => (
            <button key={s} onClick={() => setStatusFilter(s)}
              className={cn('px-3 py-1.5 rounded-xl text-xs font-medium transition-all border',
                statusFilter === s ? 'bg-accent text-white border-accent shadow-sm' : 'bg-white dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:text-text-primary hover:border-accent/30'
              )}>
              {s === 'need_manual' ? 'Needs You' : s === 'proxy_running' ? 'Proxy' : s.charAt(0).toUpperCase() + s.slice(1)}
            </button>
          ))}
          {allInteractions.length > 0 && (
            <span className="ml-auto text-xs text-text-muted">{interactions.length} items</span>
          )}
        </div>

        {isLoading ? (
          <Loading text="Loading..." />
        ) : interactions.length === 0 ? (
          <div className="flex flex-col items-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <Shield className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm">
              {statusFilter !== 'all' ? `No ${statusFilter} interactions.` : 'No authorization requests yet.'}
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {interactions.map((interaction) => (
              <ApprovalCard
                key={interaction.id}
                interaction={interaction}
                isExpanded={expandedId === interaction.id}
                onToggle={() => setExpandedId(expandedId === interaction.id ? null : interaction.id)}
                onResolve={(decision) => resolveMutation.mutate({ id: interaction.id, decision })}
                onStopProxy={() => stopProxyMutation.mutate(interaction.id)}
                isResolving={resolveMutation.isPending}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

function StatBadge({ label, value, color }) {
  return (
    <div className={cn('rounded-xl px-4 py-3 border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/50')}>
      <div className={cn('text-2xl font-bold', color)}>{value}</div>
      <div className="text-xs text-text-muted mt-0.5">{label}</div>
    </div>
  )
}

function ApprovalCard({ interaction, isExpanded, onToggle, onResolve, onStopProxy, isResolving }) {
  const Icon = TYPE_ICONS[interaction.type] || Shield
  const isActionable = interaction.status === 'pending' || interaction.status === 'need_manual'
  const isProxyRunning = interaction.status === 'proxy_running'
  const title = interaction.schema_data?.title || 'Authorization Request'
  const prompt = interaction.schema_data?.prompt || ''
  const source = interaction.context?.source || 'unknown'
  const runId = interaction.context?.run_id
  const options = interaction.schema_data?.options || []
  const reason = interaction.schema_data?.reason || interaction.context?.reason
  const objective = interaction.schema_data?.run_objective || interaction.context?.objective
  const toolName = interaction.schema_data?.tool_name || interaction.context?.tool_use?.name
  const toolInput = interaction.schema_data?.tool_input || interaction.context?.tool_use?.input

  return (
    <div className={cn(
      'border rounded-2xl bg-white dark:bg-gray-800/50 transition-all overflow-hidden',
      isActionable ? 'border-amber-400/40 shadow-md ring-1 ring-amber-400/10' :
      isExpanded ? 'border-accent/40 shadow-md' : 'border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md'
    )}>
      <div role="button" tabIndex={0} onClick={onToggle} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onToggle() } }} className="w-full text-left px-5 py-4 flex items-center gap-4 cursor-pointer">
        <div className={cn('p-2 rounded-xl',
          isActionable ? 'bg-amber-500/10 text-amber-600' :
          isProxyRunning ? 'bg-blue-500/10 text-blue-600' :
          interaction.status === 'resolved' ? 'bg-green-500/10 text-green-600' :
          'bg-gray-100 dark:bg-gray-800 text-gray-400'
        )}>
          <Icon className="w-4 h-4" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-text-primary truncate">{title}</span>
            <Badge size="sm" variant={STATUS_COLORS[interaction.status] || 'default'}>
              {interaction.status === 'need_manual' ? 'needs you' : interaction.status.replace('_', ' ')}
            </Badge>
            {interaction.resolved_by && (
              <span className="flex items-center gap-1 text-[10px] text-text-muted">
                {interaction.resolved_by === 'proxy' ? <Bot className="w-3 h-3" /> : <User className="w-3 h-3" />}
                {interaction.resolved_by}
              </span>
            )}
          </div>
          <div className="flex items-center gap-3 mt-1 text-[10px] text-text-muted">
            <span>{source}</span>
            {runId && <span className="font-mono">Run: {runId.slice(0, 8)}…</span>}
            <span>{formatRelative(interaction.inserted_at)}</span>
            {interaction.expires_at && interaction.status === 'pending' && (
              <span className="text-amber-500">Expires {formatRelative(interaction.expires_at)}</span>
            )}
          </div>
        </div>
        {isActionable && (
          <div className="flex gap-1 shrink-0" onClick={(e) => e.stopPropagation()}>
            <button onClick={() => onResolve('approved')} disabled={isResolving}
              className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-lg bg-green-500/10 text-green-600 hover:bg-green-500/20 transition-colors">
              <Check className="w-3 h-3" /> Approve
            </button>
            <button onClick={() => onResolve('denied')} disabled={isResolving}
              className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-lg bg-red-500/10 text-red-500 hover:bg-red-500/20 transition-colors">
              <X className="w-3 h-3" /> Deny
            </button>
          </div>
        )}
        {isProxyRunning && (
          <button onClick={(e) => { e.stopPropagation(); onStopProxy() }}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-medium rounded-lg bg-orange-500/10 text-orange-600 hover:bg-orange-500/20 transition-colors shrink-0">
            Stop Proxy
          </button>
        )}
        <ChevronRight className={cn('w-4 h-4 shrink-0 text-text-muted transition-transform', isExpanded && 'rotate-90')} />
      </div>

      {isExpanded && (
        <div className="px-5 pb-4 border-t border-gray-100 dark:border-gray-800 pt-3 space-y-3">
          {(prompt || reason || objective || toolName) && (
            <div className="text-sm text-text-primary bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2">
              {prompt && <p className="whitespace-pre-wrap">{prompt}</p>}
              {reason && <p><span className="font-medium">Reason:</span> {reason}</p>}
              {objective && <p className="mt-1"><span className="font-medium">Request:</span> {objective}</p>}
              {toolName && <p className="mt-1"><span className="font-medium">Tool:</span> <span className="font-mono">{toolName}</span></p>}
            </div>
          )}

          {toolInput && (
            <div>
              <span className="text-xs font-medium text-text-muted">Tool input</span>
              <pre className="mt-1 text-xs bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2 text-text-secondary overflow-auto max-h-48">
                {JSON.stringify(toolInput, null, 2)}
              </pre>
            </div>
          )}

          {options.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {options.map((opt, i) => (
                <span key={i} className="px-2 py-0.5 text-xs rounded-lg bg-gray-100 dark:bg-gray-700 text-text-secondary">
                  {opt}
                </span>
              ))}
            </div>
          )}

          {interaction.schema_data?.fields && interaction.schema_data.fields.length > 0 && (
            <div className="space-y-1.5">
              <span className="text-xs font-medium text-text-muted">Fields</span>
              {interaction.schema_data.fields.map((f, i) => (
                <div key={i} className="text-xs text-text-secondary flex gap-2">
                  <span className="font-medium">{f.label}</span>
                  <span className="text-text-muted">({f.type}{f.required ? ', required' : ''})</span>
                </div>
              ))}
            </div>
          )}

          {interaction.result && (
            <div>
              <span className="text-xs font-medium text-text-muted">Result</span>
              <div className="mt-1 text-xs bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2 text-text-secondary font-mono">
                {JSON.stringify(interaction.result)}
              </div>
            </div>
          )}

          {interaction.proxy_trail && interaction.proxy_trail.length > 0 && (
            <div>
              <span className="text-xs font-medium text-text-muted">Proxy Trail</span>
              <div className="mt-1 space-y-1">
                {interaction.proxy_trail.map((entry, i) => (
                  <div key={i} className="text-xs bg-gray-50 dark:bg-gray-800/30 rounded-lg px-3 py-2">
                    <span className="font-medium text-text-primary">{entry.action}</span>
                    {entry.reasoning && <span className="ml-2 text-text-muted">— {entry.reasoning}</span>}
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-2 text-xs text-text-muted">
            <div><span className="font-medium">Source:</span> {source}</div>
            {runId && <div><span className="font-medium">Run:</span> <Link to="/runs" className="font-mono text-accent hover:underline">{runId}</Link></div>}
            <div><span className="font-medium">Created:</span> {formatAbsolute(interaction.inserted_at)}</div>
            {interaction.expires_at && (
              <div><span className="font-medium">Expires:</span> {formatAbsolute(interaction.expires_at)}</div>
            )}
            {interaction.resolved_by && <div><span className="font-medium">Resolved by:</span> {interaction.resolved_by}</div>}
          </div>
        </div>
      )}
    </div>
  )
}
