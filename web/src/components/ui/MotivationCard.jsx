import { Lightbulb, Target, Shield, CheckCircle2 } from 'lucide-react'
import { cn } from '../../lib/utils.js'

export function MotivationCard({ motivation, successCriteria, constraints, className }) {
  return (
    <div className={cn('rounded-xl border border-card-border bg-gradient-to-br from-accent/5 to-purple-500/5 p-4', className)}>
      {/* Motivation */}
      {motivation && (
        <div className="mb-3 pb-3 border-b border-dashed border-gray-200">
          <div className="flex items-start gap-2 mb-1.5">
            <Lightbulb className="w-4 h-4 text-accent-gold shrink-0 mt-0.5" />
            <h4 className="text-xs font-semibold text-text-primary uppercase tracking-wider">Why This Matters</h4>
          </div>
          <p className="text-sm text-text-secondary pl-6 leading-relaxed">{motivation}</p>
        </div>
      )}

      {/* Success Criteria */}
      {successCriteria && Object.keys(successCriteria).length > 0 && (
        <div className="mb-3 pb-3 border-b border-dashed border-gray-200">
          <div className="flex items-start gap-2 mb-2">
            <Target className="w-4 h-4 text-accent-green shrink-0 mt-0.5" />
            <h4 className="text-xs font-semibold text-text-primary uppercase tracking-wider">Success Criteria</h4>
          </div>
          <ul className="space-y-1 pl-6">
            {Object.entries(successCriteria).map(([key, value]) => (
              <li key={key} className="flex items-start gap-2 text-sm text-text-secondary">
                <CheckCircle2 className="w-3.5 h-3.5 text-accent-green shrink-0 mt-0.5" />
                <span>{value}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Constraints */}
      {constraints && Object.keys(constraints).length > 0 && (
        <div>
          <div className="flex items-start gap-2 mb-2">
            <Shield className="w-4 h-4 text-blue-500 shrink-0 mt-0.5" />
            <h4 className="text-xs font-semibold text-text-primary uppercase tracking-wider">Constraints</h4>
          </div>
          <div className="pl-6 space-y-1">
            {Object.entries(constraints).map(([key, value]) => (
              <div key={key} className="flex items-baseline gap-2 text-sm">
                <span className="text-text-muted font-medium capitalize">{key}:</span>
                <span className="text-text-secondary">{String(value)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
