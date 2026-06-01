import { Command } from 'lucide-react'
import { useWsStore } from '../../store/wsStore'
import { NotificationBell } from './NotificationBell'
import { cn } from '../../lib/utils'

export function TopBar() {
  const connected = useWsStore((s) => s.connected)
  const activeProvider = useWsStore((s) => s.activeProvider)

  return (
    <header className="h-9 border-b border-border-light bg-[#f8f9fa] dark:bg-[#252527] flex items-center px-3 gap-2 text-xs shrink-0">
      <div className="flex items-center gap-2">
        <img src="/logo.png" alt="AIbrain" className="w-4 h-4" />
        <span className="text-[11px] font-semibold text-text-primary tracking-tight">AIbrain</span>
      </div>

      <div className="ml-auto flex items-center gap-2">
        <div className={cn(
          'flex items-center gap-1.5 px-2 py-1 rounded-md',
          connected ? 'bg-accent-green/10' : 'bg-accent-red/10'
        )}>
          <span className={cn(
            'w-1.5 h-1.5 rounded-full',
            connected ? 'bg-accent-green' : 'bg-accent-red'
          )} />
          <span className={cn(
            'text-[10px] font-medium',
            connected ? 'text-accent-green-dark' : 'text-accent-red'
          )}>
            {connected ? (activeProvider || 'Online') : 'Offline'}
          </span>
        </div>

        <button
          onClick={() => window.dispatchEvent(new CustomEvent('command-palette:open'))}
          className="hidden sm:flex items-center gap-1 px-2 py-1 rounded-md text-text-muted hover:text-text-secondary hover:bg-white/70 dark:hover:bg-white/10 transition-colors"
        >
          <Command className="w-3 h-3" />
          <span className="text-[10px]">K</span>
        </button>

        <NotificationBell />
      </div>
    </header>
  )
}
