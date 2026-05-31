import { NavLink, useLocation } from 'react-router-dom'
import {
  Home, MessageSquare, Play, Shield,
  Target, Brain, FolderOpen, Clock,
  Zap, Radio, Volume2,
  Settings, Puzzle, Wrench, User,
  Sun, Moon, ListTodo, GitBranch, BookOpen,
} from 'lucide-react'
import { cn } from '../../lib/utils'
import { getTheme, setTheme } from '../../lib/theme'

const navItems = [
  { section: 'Core', items: [
    { to: '/', icon: Home, label: 'Today' },
    { to: '/chat', icon: MessageSquare, label: 'Chat' },
    { to: '/runs', icon: Play, label: 'Runs' },
    { to: '/approvals', icon: Shield, label: 'Approvals' },
  ]},
  { section: 'Workspace', items: [
    { to: '/goals', icon: Target, label: 'Goals' },
    { to: '/memory', icon: Brain, label: 'Memory' },
    { to: '/artifacts', icon: FolderOpen, label: 'Artifacts' },
    { to: '/scheduler', icon: Clock, label: 'Scheduler' },
  ]},
  { section: 'Integrations', items: [
    { to: '/channels', icon: Radio, label: 'Channels' },
    { to: '/providers', icon: Zap, label: 'Providers' },
    { to: '/voice', icon: Volume2, label: 'Voice' },
  ]},
  { section: 'System', items: [
    { to: '/tasks', icon: ListTodo, label: 'Tasks' },
    { to: '/automation-rules', icon: GitBranch, label: 'Auto Rules' },
    { to: '/skills', icon: BookOpen, label: 'Skills' },
    { to: '/plugins', icon: Puzzle, label: 'Plugins' },
    { to: '/security', icon: Shield, label: 'Security' },
    { to: '/fs', icon: Wrench, label: 'Files' },
  ]},
]

export function Sidebar() {
  const isMac = window.electronAPI?.platform === 'darwin'
  const location = useLocation()
  const pathname = location.pathname

  return (
    <aside className={cn(
      'w-48 flex flex-col bg-[#e6eaf0] dark:bg-[#1c1c1e] border-r border-border-light/60 shrink-0 overflow-y-auto',
      isMac ? 'pt-10' : ''
    )}>
      <div className="flex-1 px-2 py-2 space-y-1">
        {navItems.map(({ section, items }) => (
          <div key={section}>
            <p className="px-3 py-1 text-[10px] font-semibold uppercase tracking-widest text-text-muted/60">
              {section}
            </p>
            {items.map(({ to, icon: Icon, label }) => {
              const isActive = to === '/' ? pathname === '/' : pathname.startsWith(to)
              return (
                <NavLink
                  key={to}
                  to={to}
                  className={cn(
                    'flex items-center gap-2.5 px-3 py-1.5 text-sm rounded-md transition-all',
                    isActive
                      ? 'bg-accent text-white font-medium'
                      : 'text-text-secondary hover:text-text-primary hover:bg-white/60 dark:hover:bg-white/10'
                  )}
                >
                  <Icon className="w-4 h-4 shrink-0" />
                  <span className="truncate">{label}</span>
                </NavLink>
              )
            })}
          </div>
        ))}
      </div>

      <div className="px-2 pb-2 pt-1 border-t border-border-light/40 mx-2">
        <button
          onClick={() => {
            const next = getTheme() === 'dark' ? 'light' : 'dark'
            setTheme(next)
          }}
          className="flex items-center gap-2.5 px-3 py-1.5 w-full text-sm rounded-md transition-all text-text-secondary hover:text-text-primary hover:bg-white/60 dark:hover:bg-white/10"
        >
          <Sun className="w-4 h-4 shrink-0 block dark:hidden" />
          <Moon className="w-4 h-4 shrink-0 hidden dark:block" />
          <span>Theme</span>
        </button>
        <NavLink
          to="/users"
          className={({ isActive }) =>
            cn(
              'flex items-center gap-2.5 px-3 py-1.5 text-sm rounded-md transition-all',
              isActive || pathname === '/profile'
                ? 'bg-accent text-white font-medium'
                : 'text-text-secondary hover:text-text-primary hover:bg-white/60 dark:hover:bg-white/10'
            )
          }
        >
          <User className="w-4 h-4 shrink-0" />
          <span>Users</span>
        </NavLink>
        <NavLink
          to="/settings"
          className={({ isActive }) =>
            cn(
              'flex items-center gap-2.5 px-3 py-1.5 text-sm rounded-md transition-all',
              isActive
                ? 'bg-accent text-white font-medium'
                : 'text-text-secondary hover:text-text-primary hover:bg-white/60 dark:hover:bg-white/10'
            )
          }
        >
          <Settings className="w-4 h-4 shrink-0" />
          <span>Settings</span>
        </NavLink>
      </div>
    </aside>
  )
}
