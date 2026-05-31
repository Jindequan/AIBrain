import { cn } from '../../../lib/utils'

export function Button({ children, className, variant = 'primary', size = 'md', icon: Icon, ...props }) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center gap-2 font-semibold rounded-xl border transition-all duration-200',
        {
          // Primary variant
          'bg-gradient-to-r from-accent to-accent-hover text-white border-transparent shadow-md shadow-accent/20 hover:shadow-lg hover:shadow-accent/30 hover:-translate-y-0.5 active:translate-y-0':
            variant === 'primary',
          // Secondary variant
          'bg-white dark:bg-gray-800 text-text-secondary border-gray-200 dark:border-gray-700 hover:border-accent/30 hover:bg-accent/5 hover:text-text-primary':
            variant === 'secondary',
          // Ghost variant
          'bg-transparent text-text-secondary border-transparent hover:bg-gray-100 dark:hover:bg-gray-800':
            variant === 'ghost',
          // Danger variant
          'bg-gradient-to-r from-red-500 to-red-600 text-white border-transparent shadow-md shadow-red-500/20 hover:shadow-lg hover:shadow-red-500/30 hover:-translate-y-0.5':
            variant === 'danger',
        },
        {
          'px-3 py-1.5 text-xs rounded-lg': size === 'sm',
          'px-4 py-2 text-sm': size === 'md',
          'px-6 py-3 text-base': size === 'lg',
        },
        className
      )}
      {...props}
    >
      {Icon && <Icon className="w-4 h-4" />}
      {children}
    </button>
  )
}

export function IconButton({ icon: Icon, className, variant = 'ghost', size = 'md', ...props }) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center rounded-xl transition-all duration-200',
        {
          'p-2 text-text-muted hover:text-text-primary hover:bg-gray-100 dark:hover:bg-gray-800': variant === 'ghost' && size === 'md',
          'p-1.5 text-text-muted hover:text-text-primary hover:bg-gray-100 dark:hover:bg-gray-800': variant === 'ghost' && size === 'sm',
          'p-3 text-text-muted hover:text-text-primary hover:bg-gray-100 dark:hover:bg-gray-800': variant === 'ghost' && size === 'lg',
          'p-2 text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-950/30': variant === 'danger' && size === 'md',
          'p-1.5 text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-950/30': variant === 'danger' && size === 'sm',
        },
        className
      )}
      {...props}
    >
      <Icon className={cn('w-4 h-4', size === 'sm' && 'w-3.5 h-3.5', size === 'lg' && 'w-5 h-5')} />
    </button>
  )
}
