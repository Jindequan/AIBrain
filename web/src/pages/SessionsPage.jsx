import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  MessageSquare, Clock, Globe, FolderOpen,
  Send, Hash, Feather, Monitor, ChevronRight,
} from 'lucide-react'
import { sessionsApi } from '../api/sessions.api'
import { formatRelative } from '../lib/time'
import {
  Card,
  IconBox,
  Badge,
  SectionHeader,
  Loading,
} from '../components/ui/design'

function channelIcon(adapter) {
  switch (adapter) {
    case 'telegram': return { Icon: Send, color: 'text-sky-500', label: 'Telegram' }
    case 'discord':  return { Icon: Hash, color: 'text-indigo-500', label: 'Discord' }
    case 'feishu':   return { Icon: Feather, color: 'text-blue-500', label: 'Feishu' }
    default:         return { Icon: Monitor, color: 'text-text-muted', label: 'Web' }
  }
}

export default function SessionsPage() {
  const navigate = useNavigate()

  const { data, isLoading, isError } = useQuery({
    queryKey: ['sessions-page'],
    queryFn: () => sessionsApi.list({ limit: 200 }),
  })

  const sessions = data?.sessions || []

  const { global, workspaceGroups } = groupSessions(sessions)

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-4xl mx-auto px-6 py-8">
        <SectionHeader
          title="Sessions"
          description={`${sessions.length} session${sessions.length !== 1 ? 's' : ''} across ${workspaceGroups.length} workspace${workspaceGroups.length !== 1 ? 's' : ''}`}
          icon={MessageSquare}
        />

        {isLoading && <Loading text="Loading sessions..." />}
        {isError && (
          <div className="flex flex-col items-center py-16">
            <p className="text-red-500 text-sm">Failed to load sessions</p>
          </div>
        )}

        {/* Global sessions */}
        {global.length > 0 && (
          <section className="mb-8 mt-6">
            <div className="flex items-center gap-2 mb-3">
              <IconBox icon={Globe} variant="info" size="sm" />
              <h2 className="text-sm font-semibold text-text-primary">Global</h2>
              <Badge size="sm" variant="default">{global.length}</Badge>
            </div>
            <SessionList sessions={global} navigate={navigate} />
          </section>
        )}

        {/* Workspace groups */}
        {workspaceGroups.map(([workspace, wsSessions], idx) => (
          <section key={idx} className="mb-8">
            <div className="flex items-center gap-2 mb-3">
              <IconBox icon={FolderOpen} variant="warning" size="sm" />
              <h2 className="text-sm font-semibold text-text-primary">
                {workspace.split('/').pop() || workspace}
              </h2>
              <Badge size="sm" variant="default">{wsSessions.length}</Badge>
            </div>
            <SessionList sessions={wsSessions} navigate={navigate} />
          </section>
        ))}

        {sessions.length === 0 && !isLoading && (
          <div className="flex flex-col items-center py-16">
            <div className="p-4 rounded-2xl bg-gradient-to-br from-gray-200 to-gray-300 dark:from-gray-700 dark:to-gray-600 mb-4">
              <MessageSquare className="w-8 h-8 text-gray-500 dark:text-gray-400" />
            </div>
            <p className="text-text-muted text-sm">No sessions yet</p>
          </div>
        )}
      </div>
    </div>
  )
}

function SessionList({ sessions, navigate }) {
  return (
    <Card variant="default" className="overflow-hidden divide-y divide-gray-100 dark:divide-gray-800">
      {sessions.map(s => (
        <SessionRow key={s.session_id} session={s} navigate={navigate} />
      ))}
    </Card>
  )
}

function SessionRow({ session, navigate }) {
  const ch = channelIcon(session.channel_adapter)

  return (
    <div
      onClick={() => navigate(`/sessions/${session.session_id}`)}
      className="flex items-center gap-4 px-5 py-3.5 hover:bg-gray-50 dark:hover:bg-gray-800/30 cursor-pointer transition-colors"
    >
      <div className="shrink-0">
        <ch.Icon className={`w-4 h-4 ${ch.color}`} />
      </div>

      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-text-primary truncate">
            {session.title || 'Untitled'}
          </p>
          <Badge size="sm" variant="default">{ch.label}</Badge>
        </div>
        <p className="text-xs text-text-muted mt-0.5 font-mono">
          {session.session_id?.slice(0, 12)}
        </p>
      </div>

      <div className="shrink-0 flex items-center gap-3">
        {session.message_count > 0 && (
          <span className="text-xs text-text-muted flex items-center gap-1">
            <MessageSquare className="w-3 h-3" />
            {session.message_count}
          </span>
        )}
        <span className="text-xs text-text-muted flex items-center gap-1">
          <Clock className="w-3 h-3" />
          {formatRelative(session.updated_at)}
        </span>
        <ChevronRight className="w-4 h-4 text-text-muted" />
      </div>
    </div>
  )
}

function groupSessions(sessions) {
  const global = []
  const workspaceMap = {}

  const sorted = [...sessions].sort(
    (a, b) => new Date(b.updated_at || 0) - new Date(a.updated_at || 0)
  )

  for (const s of sorted) {
    const ws = s.workspace_path
    if (ws && ws !== '') {
      if (!workspaceMap[ws]) workspaceMap[ws] = []
      workspaceMap[ws].push(s)
    } else {
      global.push(s)
    }
  }

  return { global, workspaceGroups: Object.entries(workspaceMap) }
}
