import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  MessageSquare, Play, Target, AlertCircle,
  Clock, RotateCw, Shield,
  Inbox, ChevronRight, Zap, Radio,
} from 'lucide-react'
import { providersApi } from '../api/providers.api'
import { channelsApi } from '../api/channels.api'
import { runsApi } from '../api/runs.api'
import { goalsApi } from '../api/goals.api'
import { interactionsApi } from '../api/interactions.api'
import { cn } from '../lib/utils'
import { SetupWizard } from '../components/setup/SetupWizard'

export default function DashboardPage() {
  const navigate = useNavigate()
  const [setupComplete, setSetupComplete] = useState(false)

  const { data: providersData, isPending: providersLoading } = useQuery({
    queryKey: ['providers'],
    queryFn: () => providersApi.list(),
  })

  const { data: channelsData } = useQuery({
    queryKey: ['channel-configs-dashboard'],
    queryFn: () => channelsApi.list(),
    staleTime: 60000,
  })

  const { data: runsData } = useQuery({
    queryKey: ['dashboard-runs'],
    queryFn: () => runsApi.list({ limit: 20 }),
    staleTime: 10000,
    refetchInterval: 15000,
  })

  const { data: goalsData } = useQuery({
    queryKey: ['dashboard-goals'],
    queryFn: () => goalsApi.list({ status: 'active' }),
    staleTime: 30000,
  })

  const { data: interactionsData } = useQuery({
    queryKey: ['dashboard-interactions'],
    queryFn: () => interactionsApi.list(),
    staleTime: 5000,
    refetchInterval: 10000,
  })

  const providers = providersData?.providers || []
  const channels = channelsData?.configs || []
  const enabledChannels = channels.filter(c => c.enabled)
  const runs = runsData?.runs || []
  const goals = goalsData?.goals || []
  const interactions = interactionsData?.interactions || []

  const activeRuns = runs.filter(r => r.status === 'running' || r.status === 'pending')
  const waitingRuns = runs.filter(r => r.status === 'waiting_approval' || r.status === 'waiting_assistant')
  const failedRuns = runs.filter(r => r.status === 'failed')
  const pendingInteractions = interactions.filter(i => i.status === 'pending')

  const needsSetup = !providersLoading && providers.length === 0 && !setupComplete
  if (needsSetup) {
    return (
      <div className="h-full">
        <SetupWizard onComplete={() => setSetupComplete(true)} />
      </div>
    )
  }

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-5xl mx-auto px-6 py-6 space-y-5">

        {/* Status row */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <StatusCard icon={Play} label="Running" value={activeRuns.length} color="blue" onClick={() => navigate('/runs')} />
          <StatusCard icon={Inbox} label="Approvals" value={pendingInteractions.length} color="amber" onClick={() => navigate('/approvals')} />
          <StatusCard icon={AlertCircle} label="Failed" value={failedRuns.length} color="red" onClick={() => navigate('/runs')} />
          <StatusCard icon={Target} label="Active Goals" value={goals.length} color="green" onClick={() => navigate('/goals')} />
        </div>

        {/* Approvals / Waiting */}
        {(pendingInteractions.length > 0 || waitingRuns.length > 0) && (
          <Section icon={Shield} title="Needs Attention" count={pendingInteractions.length + waitingRuns.length}>
            <div className="space-y-1.5">
              {pendingInteractions.map(interaction => (
                <button key={interaction.id}
                  onClick={() => navigate('/approvals')}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl bg-amber-500/5 border border-amber-500/20 hover:bg-amber-500/10 transition-colors text-left">
                  <div className="p-1.5 rounded-lg bg-amber-500/10 text-amber-600">
                    <Shield className="w-3.5 h-3.5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-medium text-text-primary truncate">
                      {interaction.schema_data?.title || interaction.type || 'Approval needed'}
                    </div>
                    <div className="text-[10px] text-text-muted">
                      {interaction.schema_data?.reason || 'Waiting for your authorization'}
                    </div>
                  </div>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
                </button>
              ))}
              {waitingRuns.slice(0, 5).map(run => (
                <button key={run.run_id}
                  onClick={() => navigate('/runs')}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl bg-purple-500/5 border border-purple-500/20 hover:bg-purple-500/10 transition-colors text-left">
                  <div className="p-1.5 rounded-lg bg-purple-500/10 text-purple-600">
                    <Clock className="w-3.5 h-3.5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-medium text-text-primary truncate">
                      {run.objective || run.title || 'Run waiting'}
                    </div>
                    <div className="text-[10px] text-text-muted">{run.status}</div>
                  </div>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
                </button>
              ))}
            </div>
          </Section>
        )}

        {/* Active Runs */}
        {activeRuns.length > 0 && (
          <Section icon={Play} title="Active Runs" count={activeRuns.length}>
            <div className="space-y-1.5">
              {activeRuns.slice(0, 5).map(run => (
                <button key={run.run_id}
                  onClick={() => navigate('/runs')}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors text-left">
                  <div className="p-1.5 rounded-lg bg-blue-500/10 text-blue-600">
                    <RotateCw className={cn('w-3.5 h-3.5', run.status === 'running' && 'animate-spin')} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-medium text-text-primary truncate">
                      {run.objective || run.title || 'Untitled run'}
                    </div>
                    <div className="text-[10px] text-text-muted">{run.source_type} &middot; {run.mode || 'manual'}</div>
                  </div>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
                </button>
              ))}
            </div>
          </Section>
        )}

        {/* Active Goals */}
        {goals.length > 0 && (
          <Section icon={Target} title="Active Goals" count={goals.length}>
            <div className="space-y-1.5">
              {goals.slice(0, 5).map(goal => (
                <button key={goal.id}
                  onClick={() => navigate('/goals')}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors text-left">
                  <div className="p-1.5 rounded-lg bg-green-500/10 text-green-600">
                    <Target className="w-3.5 h-3.5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-medium text-text-primary truncate">{goal.title}</div>
                    <div className="text-[10px] text-text-muted">Priority {goal.priority}/5</div>
                  </div>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
                </button>
              ))}
            </div>
          </Section>
        )}

        {/* Recent Failed */}
        {failedRuns.length > 0 && (
          <Section icon={AlertCircle} title="Failed Runs" count={failedRuns.length}>
            <div className="space-y-1.5">
              {failedRuns.slice(0, 3).map(run => (
                <button key={run.run_id}
                  onClick={() => navigate('/runs')}
                  className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors text-left">
                  <div className="p-1.5 rounded-lg bg-red-500/10 text-red-500">
                    <AlertCircle className="w-3.5 h-3.5" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-medium text-text-primary truncate">
                      {run.objective || run.title || 'Untitled run'}
                    </div>
                    <div className="text-[10px] text-text-muted">
                      {run.error ? run.error.slice(0, 80) : 'Failed'}
                    </div>
                  </div>
                  <ChevronRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
                </button>
              ))}
            </div>
          </Section>
        )}

        {/* System Health */}
        <Section icon={Zap} title="System" count={null}>
          <div className="grid grid-cols-3 gap-3">
            <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-gray-50 dark:bg-gray-800/30">
              <Zap className="w-4 h-4 text-accent" />
              <div>
                <div className="text-xs font-medium text-text-primary">{providers.length} Providers</div>
                <div className="text-[10px] text-text-muted">{providers.filter(p => p.available).length} healthy</div>
              </div>
            </div>
            <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-gray-50 dark:bg-gray-800/30">
              <Radio className="w-4 h-4 text-accent" />
              <div>
                <div className="text-xs font-medium text-text-primary">{enabledChannels.length} Channels</div>
                <div className="text-[10px] text-text-muted">{channels.length} configured</div>
              </div>
            </div>
            <button onClick={() => navigate('/chat')}
              className="flex items-center gap-2 px-3 py-2 rounded-xl bg-accent/5 border border-accent/20 hover:bg-accent/10 transition-colors">
              <MessageSquare className="w-4 h-4 text-accent" />
              <div>
                <div className="text-xs font-medium text-accent">New Chat</div>
                <div className="text-[10px] text-text-muted">Start a conversation</div>
              </div>
            </button>
          </div>
        </Section>
      </div>
    </div>
  )
}

function StatusCard({ icon: Icon, label, value, color, onClick }) {
  const colors = {
    blue: 'bg-blue-500/10 text-blue-600',
    amber: 'bg-amber-500/10 text-amber-600',
    red: 'bg-red-500/10 text-red-500',
    green: 'bg-green-500/10 text-green-600',
  }
  return (
    <button onClick={onClick}
      className="bg-white dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700 rounded-2xl p-4 hover:shadow-md transition-all cursor-pointer shadow-sm text-left w-full">
      <div className="flex items-center gap-3">
        <div className={cn('p-2 rounded-xl', colors[color])}>
          <Icon className="w-4 h-4" />
        </div>
        <div>
          <div className="text-lg font-bold text-text-primary tabular-nums">{value}</div>
          <div className="text-[10px] text-text-muted">{label}</div>
        </div>
      </div>
    </button>
  )
}

function Section({ icon: Icon, title, count, children }) {
  return (
    <div className="bg-white dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700 rounded-2xl shadow-sm overflow-hidden">
      <div className="flex items-center justify-between px-5 pt-4 pb-2">
        <div className="flex items-center gap-2">
          <Icon className="w-4 h-4 text-text-muted" />
          <p className="text-xs font-semibold uppercase tracking-widest text-text-muted">{title}</p>
        </div>
        {count !== null && count > 0 && (
          <span className="text-[10px] font-medium bg-accent/10 text-accent px-2 py-0.5 rounded-full">{count}</span>
        )}
      </div>
      <div className="px-4 pb-4">
        {children}
      </div>
    </div>
  )
}
