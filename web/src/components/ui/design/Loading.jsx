import { cn } from '../../../lib/utils'
import { Loader } from 'lucide-react'

export function Loading({ size = 'md', text, className }) {
  return (
    <div className={cn('flex flex-col items-center justify-center py-16', className)}>
      <div className="relative">
        <div className="absolute inset-0 bg-accent/20 rounded-full animate-ping"></div>
        <Loader className={cn('animate-spin text-accent relative', {
          'w-6 h-6': size === 'sm',
          'w-8 h-8': size === 'md',
          'w-12 h-12': size === 'lg',
        })} />
      </div>
      {text && <p className="text-sm text-text-muted mt-4">{text}</p>}
    </div>
  )
}

export function InlineLoading({ size = 'sm', className }) {
  return (
    <div className={cn('flex items-center justify-center', className)}>
      <Loader className={cn('animate-spin text-accent', {
        'w-4 h-4': size === 'sm',
        'w-5 h-5': size === 'md',
        'w-6 h-6': size === 'lg',
      })} />
    </div>
  )
}

export function Skeleton({ className, variant = 'default' }) {
  return (
    <div className={cn(
      'rounded-md bg-gray-200 dark:bg-gray-700 animate-pulse',
      {
        'h-4 w-full': variant === 'default',
        'h-8 w-32': variant === 'title',
        'h-20 w-full': variant === 'card',
        'h-10 w-10 rounded-full': variant === 'avatar',
      },
      className
    )} />
  )
}
