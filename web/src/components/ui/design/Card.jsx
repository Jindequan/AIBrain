import { cn } from '../../../lib/utils'

export function Card({ children, className, variant = 'default', ...props }) {
  return (
    <div
      className={cn(
        'rounded-2xl border transition-all duration-200',
        {
          'bg-white dark:bg-gray-800/50 border-gray-200 dark:border-gray-700/50 shadow-sm hover:shadow-md':
            variant === 'default',
          'bg-gradient-to-br from-white to-gray-50 dark:from-gray-800 dark:to-gray-900 border-gray-200/50 dark:border-gray-700/50 shadow-md':
            variant === 'elevated',
          'bg-white/80 dark:bg-gray-800/50 backdrop-blur-sm border-gray-200/50 dark:border-gray-700/50 shadow-sm':
            variant === 'glass',
        },
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}

export function CardHeader({ children, className }) {
  return <div className={cn('px-6 pt-6 pb-4', className)}>{children}</div>
}

export function CardContent({ children, className }) {
  return <div className={cn('px-6 pb-6', className)}>{children}</div>
}

export function CardFooter({ children, className }) {
  return <div className={cn('px-6 pb-6 pt-2', className)}>{children}</div>
}
