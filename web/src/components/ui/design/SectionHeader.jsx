import { cn } from '../../../lib/utils'

export function SectionHeader({ title, description, icon: Icon, action, className }) {
  return (
    <div className={cn('flex items-start justify-between mb-6', className)}>
      <div className="flex items-start gap-4">
        {Icon && (
          <div className="p-3 rounded-2xl bg-gradient-to-br from-accent to-accent-hover shadow-lg shadow-accent/25">
            <Icon className="w-6 h-6 text-white" />
          </div>
        )}
        <div>
          <h1 className="text-2xl font-bold text-text-primary mb-1">{title}</h1>
          {description && <p className="text-sm text-text-secondary">{description}</p>}
        </div>
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  )
}

export function SectionTitle({ title, count, className, badge }) {
  return (
    <div className={cn('flex items-center justify-between mb-4', className)}>
      <h2 className="text-sm font-semibold text-text-primary flex items-center gap-2">
        <span className="w-1 h-4 bg-gradient-to-b from-accent to-accent-hover rounded-full"></span>
        {title}
      </h2>
      <div className="flex items-center gap-2">
        {count !== undefined && (
          <span className="text-xs text-text-muted">
            {typeof count === 'string' ? count : `${count.current} / ${count.total} installed`}
          </span>
        )}
        {badge}
      </div>
    </div>
  )
}

export function BackButton({ to, children = 'Back', className }) {
  return (
    <a
      href={to}
      className={cn(
        'inline-flex items-center gap-2 text-sm text-text-muted hover:text-text-primary mb-4 transition-colors group',
        className
      )}
    >
      <svg className="w-4 h-4 group-hover:-translate-x-0.5 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
      </svg>
      {children}
    </a>
  )
}
