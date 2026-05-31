import { useEffect, useState } from 'react'
import { cn } from '../../lib/utils'
import { Activity, Loader2, CheckCircle } from 'lucide-react'

const TYPE_STYLES = {
  llm: 'bg-blue-50 text-blue-600 border-blue-200',
  image: 'bg-purple-50 text-purple-600 border-purple-200',
  music: 'bg-pink-50 text-pink-600 border-pink-200',
  voice: 'bg-teal-50 text-teal-600 border-teal-200',
  embedding: 'bg-orange-50 text-orange-600 border-orange-200',
}

function cooldownSeconds(cooldownUntil) {
  if (!cooldownUntil) return null
  const diff = cooldownUntil * 1000 - Date.now()
  return diff > 0 ? Math.ceil(diff / 1000) : null
}

export function ProviderCard({ provider, isActive, onTest, testResult, testPending }) {
  const [countdown, setCountdown] = useState(() => cooldownSeconds(provider.cooldown_until))

  useEffect(() => {
    if (!provider.cooldown_until) return
    const update = () => setCountdown(cooldownSeconds(provider.cooldown_until))
    const initial = setTimeout(update, 0)
    const t = setInterval(update, 1000)
    return () => {
      clearTimeout(initial)
      clearInterval(t)
    }
  }, [provider.cooldown_until])

  const visibleCountdown = provider.cooldown_until ? countdown : null

  return (
    <div className={cn(
      'rounded-xl border p-5 space-y-4 transition-all bg-card-bg',
      isActive ? 'border-accent ring-1 ring-accent/20 shadow-sm' : 'border-card-border hover:border-accent/20 hover:shadow-sm'
    )}>
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="font-semibold text-text-primary text-sm truncate">{provider.name}</h3>
            <span className={cn('text-[10px] px-1.5 py-0.5 rounded font-medium uppercase border', TYPE_STYLES[provider.type] || TYPE_STYLES.llm)}>
              {provider.type || 'llm'}
            </span>
          </div>
          <p className="text-xs text-text-muted mt-0.5">Priority {provider.priority}</p>
        </div>
        <span className={cn(
          'flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full font-medium',
          provider.available
            ? 'bg-accent-green/10 text-accent-green'
            : 'bg-red-50 text-red-500'
        )}>
          <span className={cn('w-1.5 h-1.5 rounded-full', provider.available ? 'bg-accent-green' : 'bg-red-500')} />
          {provider.available ? 'Healthy' : visibleCountdown ? `Wait ${visibleCountdown}s` : provider.unavailable_reason || 'Down'}
        </span>
      </div>

      {/* Model mappings */}
      {Object.keys(provider.models || {}).length > 0 && (
        <div>
          <p className="text-[10px] font-medium text-text-muted uppercase tracking-wider mb-1.5">
            {provider.type === 'llm' ? 'LLM Models' : 'Models'}
          </p>
          <div className="space-y-1">
            {Object.entries(provider.models).map(([key, model]) => (
              <div key={key} className="flex gap-2 text-[11px] font-mono bg-gray-50 rounded-lg px-2.5 py-1.5">
                <span className="text-text-secondary">
                  {provider.type === 'llm' ? (key === 'normal' ? '💬' : '⚡') : '🔧'}
                </span>
                <span className="text-text-muted">
                  {provider.type === 'llm' ? (key === 'normal' ? 'Normal' : 'Lite') : 'Default'}
                </span>
                <span className="text-text-muted">→</span>
                <span className="text-accent font-medium truncate">{model}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Endpoints */}
      {Object.keys(provider.endpoints || {}).length > 0 && (
        <div>
          <p className="text-[10px] font-medium text-text-muted uppercase tracking-wider mb-1.5">Endpoints</p>
          {Object.entries(provider.endpoints).map(([proto, url]) => (
            <p key={proto} className="text-[11px] font-mono text-text-secondary truncate bg-gray-50 rounded-lg px-2.5 py-1.5 mb-1">
              <span className={cn('font-medium', proto === 'openai' ? 'text-blue-500' : 'text-amber-600')}>{proto}</span>
              <span className="text-text-muted"> {url}</span>
            </p>
          ))}
        </div>
      )}

      {/* Test button */}
      {onTest && (
        <div className="flex items-center gap-2 pt-1">
          <button
            onClick={(e) => { e.stopPropagation(); onTest(provider.name) }}
            disabled={testPending}
            className="flex items-center gap-1.5 text-[11px] px-3 py-1.5 rounded-lg bg-gray-50 hover:bg-gray-100 text-text-secondary disabled:opacity-40 transition-colors border border-card-border"
          >
            {testPending ? <Loader2 className="w-3 h-3 animate-spin" /> : <Activity className="w-3 h-3" />}
            Test Connection
          </button>
          {testResult && (
            <span className={cn(
              'text-[10px] px-2 py-0.5 rounded-full font-medium',
              testResult.ok ? 'bg-accent-green/10 text-accent-green' : 'bg-red-50 text-red-500'
            )}>
              {testResult.ok ? <CheckCircle className="w-3 h-3 inline mr-0.5" /> : null}
              {testResult.ok ? `${testResult.latency_ms || 'ok'}ms` : 'Failed'}
            </span>
          )}
        </div>
      )}
    </div>
  )
}
