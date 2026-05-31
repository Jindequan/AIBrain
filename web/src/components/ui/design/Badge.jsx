import { cn } from '../../../lib/utils'

export function Badge({ children, className, variant = 'default', size = 'md', icon: Icon }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 font-medium rounded-full border transition-all duration-200',
        {
          // Default variant
          'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 border-gray-200 dark:border-gray-700':
            variant === 'default',
          // Primary variant
          'bg-accent/10 text-accent border-accent/20': variant === 'primary',
          // Success variant
          'bg-emerald-50 dark:bg-emerald-950/50 text-emerald-700 dark:text-emerald-400 border-emerald-200 dark:border-emerald-800':
            variant === 'success',
          // Warning variant
          'bg-amber-50 dark:bg-amber-950/50 text-amber-700 dark:text-amber-400 border-amber-200 dark:border-amber-800':
            variant === 'warning',
          // Danger variant
          'bg-red-50 dark:bg-red-950/50 text-red-700 dark:text-red-400 border-red-200 dark:border-red-800':
            variant === 'danger',
          // Info variant
          'bg-blue-50 dark:bg-blue-950/50 text-blue-700 dark:text-blue-400 border-blue-200 dark:border-blue-800':
            variant === 'info',
          // Gradient variant
          'bg-gradient-to-r from-accent to-accent-hover text-white border-transparent shadow-sm':
            variant === 'gradient',
        },
        {
          'px-2 py-0.5 text-[10px] rounded-md': size === 'sm',
          'px-2.5 py-1 text-xs rounded-full': size === 'md',
          'px-3 py-1.5 text-sm rounded-full': size === 'lg',
        },
        className
      )}
    >
      {Icon && <Icon className="w-3 h-3" />}
      {children}
    </span>
  )
}

export function DotBadge({ color = 'emerald', className }) {
  return (
    <span
      className={cn(
        'inline-block rounded-full shadow-sm transition-all duration-200',
        {
          'w-2 h-2 bg-gradient-to-br from-emerald-400 to-teal-500 shadow-emerald-500/30': color === 'emerald',
          'w-2 h-2 bg-gradient-to-br from-amber-400 to-orange-500 shadow-amber-500/30': color === 'amber',
          'w-2 h-2 bg-gradient-to-br from-red-400 to-rose-500 shadow-red-500/30': color === 'red',
          'w-2 h-2 bg-gradient-to-br from-blue-400 to-indigo-500 shadow-blue-500/30': color === 'blue',
          'w-2 h-2 bg-gray-300 dark:bg-gray-600': color === 'gray',
          'w-2.5 h-2.5': className?.includes('w-2.5'),
        },
        className
      )}
    />
  )
}
