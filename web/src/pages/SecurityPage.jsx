import { useQuery } from '@tanstack/react-query'
import { Shield, AlertTriangle, Eye, Check, X, ChevronRight } from 'lucide-react'
import { toolsApi } from '../api/tools.api'
import { cn } from '../lib/utils'
import { SectionHeader, Loading } from '../components/ui/design'

const RISK_COLORS = {
  read_only: 'bg-green-500/10 text-green-600 border-green-500/20',
  workspace_write: 'bg-blue-500/10 text-blue-600 border-blue-500/20',
  network: 'bg-purple-500/10 text-purple-600 border-purple-500/20',
  shell_exec: 'bg-red-500/10 text-red-600 border-red-500/20',
  unknown: 'bg-gray-500/10 text-gray-500 border-gray-500/20',
}

const RISK_ORDER = { shell_exec: 0, workspace_write: 1, network: 2, read_only: 3 }

const PERMISSION_MODES = [
  {
    mode: 'execute',
    label: 'Execute',
    icon: Check,
    color: 'text-green-600',
    description: 'All tools allowed. Used for internal/programmatic calls and trusted autonomous runs.',
    allows: 'All tools, all risk categories',
  },
  {
    mode: 'plan',
    label: 'Plan',
    icon: Eye,
    color: 'text-blue-600',
    description: 'Read-only tools only. Used for research, analysis, and planning without side effects.',
    allows: 'Read-only tools only (search, read, grep)',
  },
  {
    mode: 'approval_required',
    label: 'Approval Required',
    icon: AlertTriangle,
    color: 'text-amber-600',
    description: 'Read-only tools auto-allowed. Write/network tools require user approval. Shell exec always requires manual approval.',
    allows: 'Read-only: auto. Others: per-use approval or proxy',
  },
]

export default function SecurityPage() {
  const { data: toolsData, isLoading } = useQuery({
    queryKey: ['tools'],
    queryFn: () => toolsApi.list(),
  })

  const tools = (toolsData?.tools || []).sort((a, b) => {
    const aRisk = RISK_ORDER[a.risk_category] ?? 99
    const bRisk = RISK_ORDER[b.risk_category] ?? 99
    return aRisk - bRisk
  })

  const riskCounts = tools.reduce((acc, t) => {
    const cat = t.risk_category || 'unknown'
    acc[cat] = (acc[cat] || 0) + 1
    return acc
  }, {})

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-5xl mx-auto px-6 py-8">
        <SectionHeader title="Security" description="Permission rules and tool risk categories" icon={Shield} />

        {isLoading ? (
          <Loading text="Loading..." />
        ) : (
          <div className="space-y-6 mt-6">
            {/* Permission Modes */}
            <section>
              <h3 className="text-sm font-semibold text-text-primary mb-3">Permission Modes</h3>
              <div className="grid grid-cols-3 gap-3">
                {PERMISSION_MODES.map((pm) => (
                  <div key={pm.mode} className="border border-gray-200 dark:border-gray-700 rounded-2xl bg-white dark:bg-gray-800/50 p-4">
                    <div className="flex items-center gap-2 mb-2">
                      <pm.icon className={cn('w-4 h-4', pm.color)} />
                      <span className="text-sm font-bold text-text-primary">{pm.label}</span>
                    </div>
                    <p className="text-xs text-text-secondary mb-2">{pm.description}</p>
                    <span className="text-[10px] text-text-muted bg-gray-50 dark:bg-gray-800/30 rounded-lg px-2 py-1">
                      {pm.allows}
                    </span>
                  </div>
                ))}
              </div>
            </section>

            {/* Tool Risk Matrix */}
            <section>
              <h3 className="text-sm font-semibold text-text-primary mb-3">
                Tool Risk Categories
                <span className="ml-2 text-xs font-normal text-text-muted">{tools.length} tools</span>
              </h3>

              {/* Risk summary bar */}
              <div className="flex items-center gap-3 mb-3">
                {Object.entries(RISK_COLORS).map(([cat, colors]) => {
                  const count = riskCounts[cat] || 0
                  if (count === 0) return null
                  return (
                    <div key={cat} className={cn('flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs border', colors)}>
                      {cat.replace('_', ' ')}
                      <span className="font-bold">{count}</span>
                    </div>
                  )
                })}
              </div>

              <div className="border border-gray-200 dark:border-gray-700 rounded-2xl bg-white dark:bg-gray-800/50 overflow-hidden">
                <div className="grid grid-cols-12 gap-2 px-4 py-2 text-[10px] font-semibold uppercase tracking-wider text-text-muted border-b border-gray-100 dark:border-gray-800">
                  <span className="col-span-3">Tool</span>
                  <span className="col-span-5">Description</span>
                  <span className="col-span-2">Risk Category</span>
                  <span className="col-span-2 text-right">Read-only</span>
                </div>
                {tools.map((tool) => (
                  <div key={tool.name} className="grid grid-cols-12 gap-2 px-4 py-2.5 text-xs border-b border-gray-50 dark:border-gray-800/50 last:border-0 hover:bg-gray-50 dark:hover:bg-gray-800/30 items-center">
                    <span className="col-span-3 font-mono font-medium text-text-primary truncate">{tool.name}</span>
                    <span className="col-span-5 text-text-secondary truncate">{tool.description || '—'}</span>
                    <span className="col-span-2">
                      <span className={cn('px-2 py-0.5 rounded-md text-[10px] font-medium border', RISK_COLORS[tool.risk_category] || RISK_COLORS.unknown)}>
                        {(tool.risk_category || 'unknown').replace('_', ' ')}
                      </span>
                    </span>
                    <span className="col-span-2 text-right">
                      {tool.read_only ? (
                        <Check className="w-3.5 h-3.5 text-green-500 ml-auto" />
                      ) : (
                        <X className="w-3.5 h-3.5 text-red-400 ml-auto" />
                      )}
                    </span>
                  </div>
                ))}
              </div>
            </section>

            {/* How it works */}
            <section>
              <h3 className="text-sm font-semibold text-text-primary mb-3">How Authorization Works</h3>
              <div className="border border-gray-200 dark:border-gray-700 rounded-2xl bg-white dark:bg-gray-800/50 p-5">
                <div className="flex items-center gap-3 text-xs text-text-secondary">
                  <div className="flex flex-col items-center gap-1">
                    <span className="px-2 py-0.5 rounded-lg bg-gray-100 dark:bg-gray-700 text-text-primary font-medium">Run starts</span>
                  </div>
                  <ChevronRight className="w-3 h-3 text-text-muted" />
                  <div className="flex flex-col items-center gap-1">
                    <span className="px-2 py-0.5 rounded-lg bg-blue-500/10 text-blue-600 font-medium">Capability Check</span>
                    <span className="text-[10px] text-text-muted">Can the system do this?</span>
                  </div>
                  <ChevronRight className="w-3 h-3 text-text-muted" />
                  <div className="flex flex-col items-center gap-1">
                    <span className="px-2 py-0.5 rounded-lg bg-amber-500/10 text-amber-600 font-medium">Permission Gate</span>
                    <span className="text-[10px] text-text-muted">Should the system do this?</span>
                  </div>
                  <ChevronRight className="w-3 h-3 text-text-muted" />
                  <div className="flex flex-col items-center gap-1">
                    <span className="px-2 py-0.5 rounded-lg bg-purple-500/10 text-purple-600 font-medium">Per-Tool Auth</span>
                    <span className="text-[10px] text-text-muted">Approve/deny each tool use</span>
                  </div>
                  <ChevronRight className="w-3 h-3 text-text-muted" />
                  <div className="flex flex-col items-center gap-1">
                    <span className="px-2 py-0.5 rounded-lg bg-green-500/10 text-green-600 font-medium">Execution or Denial</span>
                    <span className="text-[10px] text-text-muted">Tool runs or gets permission error</span>
                  </div>
                </div>

                <div className="mt-4 pt-3 border-t border-gray-100 dark:border-gray-800">
                  <div className="grid grid-cols-2 gap-4 text-xs text-text-secondary">
                    <div>
                      <span className="font-medium text-text-primary">Proxy Auto-Approval</span>
                      <p className="mt-0.5">When enabled, the AI Proxy evaluates approval requests and can auto-resolve low-risk confirmations based on context and historical feedback.</p>
                    </div>
                    <div>
                      <span className="font-medium text-text-primary">Escalation to Manual</span>
                      <p className="mt-0.5">Shell exec, high-risk operations, and anything the Proxy is uncertain about are escalated for manual user approval. Timeout after 5 minutes.</p>
                    </div>
                  </div>
                </div>
              </div>
            </section>
          </div>
        )}
      </div>
    </div>
  )
}
