import { AlertCircle, Loader2 } from 'lucide-react'
import { cn } from '../../lib/utils'

export function Loading() {
  return (
    <div className="flex items-center justify-center h-full min-h-[200px]">
      <Loader2 className="w-5 h-5 text-accent animate-spin" />
    </div>
  )
}

export function ErrorDisplay({ message, className }) {
  if (!message) return null
  return (
    <div className={cn(
      'flex items-center gap-2 px-4 py-3 rounded-xl bg-red-50 border border-red-200 text-sm text-red-700',
      className
    )}>
      <AlertCircle className="w-4 h-4 shrink-0" />
      <span>{message}</span>
    </div>
  )
}
