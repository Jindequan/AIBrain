import { FolderOpen } from 'lucide-react'

/**
 * Consistent empty state for list pages.
 */
export function EmptyState({ icon: Icon = FolderOpen, title, description, action }) {
  return (
    <div className="flex flex-col items-center justify-center py-12 px-4 text-center">
      <div className="p-3 rounded-xl bg-gray-100 dark:bg-gray-800/50 mb-3">
        <Icon className="w-6 h-6 text-text-muted" />
      </div>
      <p className="text-sm font-medium text-text-secondary">{title || 'No items found'}</p>
      {description && <p className="text-xs text-text-muted mt-1 max-w-xs">{description}</p>}
      {action && <div className="mt-3">{action}</div>}
    </div>
  )
}
