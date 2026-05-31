import { Link } from 'react-router-dom'
import { Target, FolderKanban, Sparkles, ArrowRight } from 'lucide-react'
import { cn } from '../../lib/utils.js'

export function RelatedItemsCard({ title, items, type, emptyMessage }) {
  const getTypeConfig = () => {
    switch (type) {
      case 'objectives':
        return {
          icon: Target,
          color: 'text-accent',
          bgColor: 'bg-accent/10',
        }
      case 'projects':
        return {
          icon: FolderKanban,
          color: 'text-purple-500',
          bgColor: 'bg-purple-500/10',
        }
      case 'plans':
        return {
          icon: Sparkles,
          color: 'text-accent-gold',
          bgColor: 'bg-accent-gold/10',
        }
      default:
        return {
          icon: Target,
          color: 'text-text-muted',
          bgColor: 'bg-gray-100',
        }
    }
  }

  const config = getTypeConfig()
  const Icon = config.icon

  return (
    <div className="rounded-xl border border-card-border bg-card-bg overflow-hidden">
      <div className={cn('px-4 py-2.5 border-b border-card-border flex items-center gap-2', config.bgColor)}>
        <Icon className={cn('w-4 h-4', config.color)} />
        <h3 className="text-xs font-semibold text-text-primary">{title}</h3>
        <span className="text-[10px] text-text-muted ml-auto">{items.length}</span>
      </div>

      <div className="divide-y divide-card-border">
        {items.length === 0 ? (
          <p className="px-4 py-6 text-center text-text-muted text-xs">{emptyMessage}</p>
        ) : (
          items.slice(0, 5).map((item) => (
            <Link
              key={item.id}
              to={
                type === 'objectives' ? `/objectives/${item.id}` :
                type === 'projects' ? `/projects/${item.id}` :
                `/projects/${item.project_id}/plan/${item.id}`
              }
              className="px-4 py-2.5 flex items-center gap-3 hover:bg-gray-50 transition-colors group"
            >
              <div className="flex-1 min-w-0">
                <p className="text-sm text-text-primary truncate group-hover:text-accent transition-colors">
                  {item.title}
                </p>
                {item.description && (
                  <p className="text-xs text-text-muted truncate">{item.description}</p>
                )}
              </div>
              <ArrowRight className="w-3.5 h-3.5 text-text-muted shrink-0" />
            </Link>
          ))
        )}
      </div>

      {items.length > 5 && (
        <div className="px-4 py-2 border-t border-card-border">
          <p className="text-xs text-text-muted text-center">
            And {items.length - 5} more {type}...
          </p>
        </div>
      )}
    </div>
  )
}
