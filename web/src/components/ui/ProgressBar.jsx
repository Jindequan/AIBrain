import { cn } from '../../lib/utils.js'

export function ProgressBar({ value, max = 100, size = 'md', showLabel = true, className }) {
  const percentage = max > 0 ? Math.round((value / max) * 100) : 0

  const sizeStyles = {
    sm: 'h-1',
    md: 'h-2',
    lg: 'h-3',
  }

  return (
    <div className={cn('flex items-center gap-2', className)}>
      <div className={cn('flex-1 bg-gray-200 rounded-full overflow-hidden', sizeStyles[size])}>
        <div
          className={cn(
            'h-full transition-all duration-500 ease-out',
            percentage >= 100 ? 'bg-accent-green' :
            percentage >= 75 ? 'bg-accent' :
            percentage >= 50 ? 'bg-accent-gold' :
            percentage >= 25 ? 'bg-orange-400' :
            'bg-red-500'
          )}
          style={{ width: `${percentage}%` }}
        />
      </div>
      {showLabel && (
        <span className={cn(
          'font-medium tabular-nums',
          percentage >= 100 ? 'text-accent-green' :
          percentage >= 50 ? 'text-accent' :
          'text-text-muted'
        )}>
          {percentage}%
        </span>
      )}
    </div>
  )
}
