import { cn } from '../../../lib/utils'
import { CheckCircle, Sparkles, AlertTriangle, Info, XCircle } from 'lucide-react'

const statusConfig = {
  success: {
    icon: CheckCircle,
    gradient: 'from-emerald-50 to-teal-50 dark:from-emerald-950/30 dark:to-teal-950/30',
    border: 'border-emerald-200 dark:border-emerald-800/50',
    iconGradient: 'from-emerald-500 to-teal-600',
    iconShadow: 'shadow-emerald-500/25',
    textTitle: 'text-emerald-900 dark:text-emerald-100',
    textBody: 'text-emerald-700 dark:text-emerald-400',
    badgeBg: 'bg-emerald-100 dark:bg-emerald-900/50',
    badgeText: 'text-emerald-600 dark:text-emerald-400',
  },
  warning: {
    icon: AlertTriangle,
    gradient: 'from-amber-50 to-orange-50 dark:from-amber-950/30 dark:to-orange-950/30',
    border: 'border-amber-200 dark:border-amber-800/50',
    iconGradient: 'from-amber-500 to-orange-600',
    iconShadow: 'shadow-amber-500/25',
    textTitle: 'text-amber-900 dark:text-amber-100',
    textBody: 'text-amber-700 dark:text-amber-400',
    badgeBg: 'bg-amber-100 dark:bg-amber-900/50',
    badgeText: 'text-amber-600 dark:text-amber-400',
  },
  info: {
    icon: Info,
    gradient: 'from-blue-50 to-indigo-50 dark:from-blue-950/30 dark:to-indigo-950/30',
    border: 'border-blue-200 dark:border-blue-800/50',
    iconGradient: 'from-blue-500 to-indigo-600',
    iconShadow: 'shadow-blue-500/25',
    textTitle: 'text-blue-900 dark:text-blue-100',
    textBody: 'text-blue-700 dark:text-blue-400',
    badgeBg: 'bg-blue-100 dark:bg-blue-900/50',
    badgeText: 'text-blue-600 dark:text-blue-400',
  },
  error: {
    icon: XCircle,
    gradient: 'from-red-50 to-rose-50 dark:from-red-950/30 dark:to-rose-950/30',
    border: 'border-red-200 dark:border-red-800/50',
    iconGradient: 'from-red-500 to-rose-600',
    iconShadow: 'shadow-red-500/25',
    textTitle: 'text-red-900 dark:text-red-100',
    textBody: 'text-red-700 dark:text-red-400',
    badgeBg: 'bg-red-100 dark:bg-red-900/50',
    badgeText: 'text-red-600 dark:text-red-400',
  },
  empty: {
    icon: Sparkles,
    gradient: 'from-gray-50 to-slate-50 dark:from-gray-950/30 dark:to-slate-950/30',
    border: 'border-gray-200 dark:border-gray-800/50',
    iconGradient: 'from-gray-500 to-slate-600',
    iconShadow: 'shadow-gray-500/25',
    textTitle: 'text-gray-900 dark:text-gray-100',
    textBody: 'text-gray-700 dark:text-gray-400',
    badgeBg: 'bg-gray-100 dark:bg-gray-900/50',
    badgeText: 'text-gray-600 dark:text-gray-400',
  },
}

export function StatusCard({ status = 'info', title, value, badge, description, className }) {
  const config = statusConfig[status] || statusConfig.info
  const Icon = config.icon

  return (
    <div
      className={cn(
        'rounded-2xl border p-6 transition-all duration-300 shadow-sm',
        `bg-gradient-to-r ${config.gradient}`,
        config.border,
        className
      )}
    >
      <div className="flex items-start gap-4">
        <div className={cn(
          'p-3 rounded-2xl shadow-md transition-all duration-300',
          `bg-gradient-to-br ${config.iconGradient}`,
          config.iconShadow
        )}>
          <Icon className="w-5 h-5 text-white" />
        </div>
        <div className="flex-1">
          <p className={cn('text-sm font-semibold mb-1', config.textTitle)}>
            {title}
          </p>
          {value && (
            <div className="flex items-baseline gap-2 mb-1">
              <span className={cn('text-xl font-bold', config.textTitle)}>{value}</span>
              {badge && (
                <span className={cn('text-xs px-2 py-0.5 rounded-full font-medium', config.badgeBg, config.badgeText)}>
                  {badge}
                </span>
              )}
            </div>
          )}
          {description && (
            <p className={cn('text-xs', config.textBody)}>
              {description}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}

export function CompactStatusCard({ status = 'info', title, description, className }) {
  const config = statusConfig[status] || statusConfig.info
  const Icon = config.icon

  return (
    <div
      className={cn(
        'rounded-2xl border p-4 transition-all duration-300',
        `bg-gradient-to-r ${config.gradient}`,
        config.border,
        className
      )}
    >
      <div className="flex items-center gap-3">
        <div className={cn(
          'p-2 rounded-xl shadow-sm',
          `bg-gradient-to-br ${config.iconGradient}`,
          config.iconShadow
        )}>
          <Icon className="w-4 h-4 text-white" />
        </div>
        <div className="flex-1 min-w-0">
          <p className={cn('text-sm font-semibold', config.textTitle)}>
            {title}
          </p>
          {description && (
            <p className={cn('text-xs mt-0.5', config.textBody)}>
              {description}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
