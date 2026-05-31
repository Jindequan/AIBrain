import { cn } from '../../../lib/utils'

export function IconBox({ icon: Icon, variant = 'default', size = 'md', className, ...props }) {
  return (
    <div
      className={cn(
        'inline-flex items-center justify-center rounded-xl shadow-sm transition-all duration-200',
        {
          // Default variant
          'bg-gradient-to-br from-accent to-accent-hover shadow-accent/25': variant === 'accent',
          // Primary color
          'bg-gradient-to-br from-blue-500 to-indigo-600 shadow-blue-500/25': variant === 'primary',
          // Success
          'bg-gradient-to-br from-emerald-500 to-teal-600 shadow-emerald-500/25': variant === 'success',
          // Warning
          'bg-gradient-to-br from-amber-500 to-orange-600 shadow-amber-500/25': variant === 'warning',
          // Danger
          'bg-gradient-to-br from-red-500 to-rose-600 shadow-red-500/25': variant === 'danger',
          // Info
          'bg-gradient-to-br from-violet-500 to-purple-600 shadow-violet-500/25': variant === 'info',
          // Gray
          'bg-gradient-to-br from-gray-400 to-gray-500 shadow-gray-500/25': variant === 'gray',
          // Custom gradient (via className)
          'shadow-md': variant === 'custom',
        },
        {
          'p-2': size === 'sm',
          'p-2.5': size === 'md',
          'p-3': size === 'lg',
        },
        className
      )}
      {...props}
    >
      <Icon className={cn('text-white', size === 'sm' && 'w-4 h-4', size === 'md' && 'w-4 h-4', size === 'lg' && 'w-5 h-5')} />
    </div>
  )
}

export function GradientIconBox({ icon: Icon, gradient, size = 'md', className, ...props }) {
  return (
    <div
      className={cn(
        'inline-flex items-center justify-center rounded-xl shadow-sm transition-transform duration-200 group-hover:scale-105',
        {
          'p-2': size === 'sm',
          'p-2.5': size === 'md',
          'p-3': size === 'lg',
        },
        `bg-gradient-to-br ${gradient}`,
        className
      )}
      {...props}
    >
      <Icon className={cn('text-white', size === 'sm' && 'w-4 h-4', size === 'md' && 'w-4 h-4', size === 'lg' && 'w-5 h-5')} />
    </div>
  )
}
