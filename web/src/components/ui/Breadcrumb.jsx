import { ChevronRight, Home } from 'lucide-react'
import { Link } from 'react-router-dom'
import { cn } from '../../lib/utils.js'

export function Breadcrumb({ items, className }) {
  return (
    <nav className={cn('flex items-center gap-1 text-sm', className)}>
      <Link
        to="/"
        className="p-1 rounded-lg hover:bg-gray-100 text-text-muted hover:text-text-primary transition-colors"
        title="Home"
      >
        <Home className="w-4 h-4" />
      </Link>

      {items.map((item, index) => (
        <div key={index} className="flex items-center gap-1">
          <ChevronRight className="w-4 h-4 text-text-muted" />
          {item.href ? (
            <Link
              to={item.href}
              className="px-2 py-1 rounded-lg hover:bg-gray-100 text-text-muted hover:text-text-primary transition-colors truncate max-w-[150px]"
              title={item.label}
            >
              {item.icon && <span className="mr-1">{item.icon}</span>}
              {item.label}
            </Link>
          ) : (
            <span className="px-2 py-1 rounded-lg bg-gray-100 text-text-primary font-medium truncate max-w-[150px]" title={item.label}>
              {item.icon && <span className="mr-1">{item.icon}</span>}
              {item.label}
            </span>
          )}
        </div>
      ))}
    </nav>
  )
}
