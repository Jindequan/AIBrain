import { useEffect, lazy, Suspense } from 'react'
import { Routes, Route, useNavigate } from 'react-router-dom'
import { Sidebar } from './components/layout/Sidebar'
import { TopBar } from './components/layout/TopBar'
import TitleBar from './components/desktop/TitleBar'
import { ToastContainer } from './components/ui/ToastContainer'
import { CommandPalette } from './components/ui/CommandPalette'
import { ErrorBoundary } from './components/ui/ErrorBoundary'
import { useKeyboardShortcuts } from './hooks/useKeyboardShortcuts'
import { useWsStore } from './store/wsStore'
import { useToastStore } from './store/toastStore'
import { setGlobalErrorHandler } from './api/client'
import { getTheme, setTheme } from './lib/theme'
import { useInteractionStore } from './store/interactionStore'
import { InteractionModal } from './components/interaction/InteractionModal'
import { interactionsApi } from './api/interactions.api'

// Lazy-loaded pages
const DashboardPage = lazy(() => import('./pages/DashboardPage'))
const ChatPage = lazy(() => import('./pages/ChatPage'))
const ChannelsPage = lazy(() => import('./pages/ChannelsPage'))
const GoalsPage = lazy(() => import('./pages/GoalsPage'))
const TasksPage = lazy(() => import('./pages/TasksPage'))
const ProvidersPage = lazy(() => import('./pages/ProvidersPage'))
const SessionsPage = lazy(() => import('./pages/SessionsPage'))

const ApprovalsPage = lazy(() => import('./pages/ApprovalsPage'))
const ArtifactsPage = lazy(() => import('./pages/ArtifactsPage'))
const AutomationRulesPage = lazy(() => import('./pages/AutomationRulesPage'))
const FileBrowserPage = lazy(() => import('./pages/FileBrowserPage'))
const SchedulerPage = lazy(() => import('./pages/SchedulerPage'))
const SecurityPage = lazy(() => import('./pages/SecurityPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const MemoryPage = lazy(() => import('./pages/MemoryPage'))
const SkillsPage = lazy(() => import('./pages/SkillsPage'))
const RunsPage = lazy(() => import('./pages/RunsPage'))
const PluginsPage = lazy(() => import('./pages/PluginsPage'))
const VoiceSettingsPage = lazy(() => import('./pages/VoiceSettingsPage'))
const ProfilePage = lazy(() => import('./pages/ProfilePage'))
const UsersPage = lazy(() => import('./pages/UsersPage'))

function PageLoading() {
  return (
    <div className="flex items-center justify-center h-full bg-main-bg">
      <div className="flex flex-col items-center gap-2">
        <div className="w-5 h-5 border-2 border-accent border-t-transparent rounded-full animate-spin" />
        <span className="text-xs text-text-muted">Loading...</span>
      </div>
    </div>
  )
}

export default function App() {
  const navigate = useNavigate()
  const connect = useWsStore((s) => s.connect)
  const subscribe = useWsStore((s) => s.subscribe)
  useKeyboardShortcuts()
  const { addToast } = useToastStore()

  // Global API error handler — shows toast for unhandled errors
  useEffect(() => {
    setGlobalErrorHandler((error) => {
      if (error.status === 401) {
        addToast({ title: 'Unauthorized', message: 'Please check your credentials', variant: 'error' })
      } else if (error.status === 403) {
        addToast({ title: 'Forbidden', message: error.message, variant: 'error' })
      } else if (error.status >= 500) {
        addToast({ title: 'Server Error', message: error.message, variant: 'error' })
      }
      // 400/404/422 are expected errors — individual mutations handle them via onError
    })
    return () => setGlobalErrorHandler(null)
  }, [addToast])

  useEffect(() => { connect() }, [connect])

  useEffect(() => {
    return subscribe((msg) => {
      if (msg.type !== 'notification') return

      if (msg.event === 'interaction_needed') {
        const interactionId = msg.data?.interaction_id
        if (interactionId) {
          window.dispatchEvent(new CustomEvent('interaction-needed', { detail: { interaction_id: interactionId } }))
        }
      }

      if (msg.event === 'interaction_escalated') {
        const interactionId = msg.data?.interaction_id
        if (interactionId) {
          window.dispatchEvent(new CustomEvent('interaction-escalated', { detail: { interaction_id: interactionId } }))
        }
      }
    })
  }, [subscribe])

  // Listen for navigation events from Electron menu / titlebar
  useEffect(() => {
    const handleNavigate = (e) => {
      if (e.detail) navigate(e.detail)
    }
    window.addEventListener('navigate', handleNavigate)
    return () => window.removeEventListener('navigate', handleNavigate)
  }, [navigate])

  // Initialize dark mode from stored preference
  useEffect(() => {
    const theme = getTheme()
    setTheme(theme)
  }, [])

  // Listen for interaction events via custom event (from useChatWebSocket hook)
  useEffect(() => {
    const handleInteractionNeeded = async (e) => {
      const interactionId = e.detail?.interaction_id
      if (!interactionId) return

      try {
        const response = await interactionsApi.get(interactionId)
        useInteractionStore.getState().addInteraction(response.interaction)
      } catch (error) {
        console.error('Failed to fetch interaction:', error)
      }
    }

    const handleInteractionResolved = (e) => {
      const interactionId = e.detail?.interaction_id
      if (!interactionId) return

      useInteractionStore.getState().removeInteraction(interactionId)
    }

    const handleInteractionEscalated = (e) => {
      const interactionId = e.detail?.interaction_id
      if (!interactionId) return

      useInteractionStore.getState().updateInteraction(interactionId, { status: 'need_manual' })
    }

    window.addEventListener('interaction-needed', handleInteractionNeeded)
    window.addEventListener('interaction-resolved', handleInteractionResolved)
    window.addEventListener('interaction-escalated', handleInteractionEscalated)

    return () => {
      window.removeEventListener('interaction-needed', handleInteractionNeeded)
      window.removeEventListener('interaction-resolved', handleInteractionResolved)
      window.removeEventListener('interaction-escalated', handleInteractionEscalated)
    }
  }, [])

  return (
    <div className="h-screen flex flex-col overflow-hidden">
      <TitleBar />
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <div className="flex flex-col flex-1 overflow-hidden bg-white">
          <TopBar />
          <main className="flex-1 overflow-auto">
            <ErrorBoundary>
              <Suspense fallback={<PageLoading />}>
                <Routes>
                  <Route path="/" element={<DashboardPage />} />
                  <Route path="/chat" element={<ChatPage />} />
                  <Route path="/sessions" element={<SessionsPage />} />
                  <Route path="/sessions/:session_id" element={<ChatPage />} />
                  <Route path="/channels" element={<ChannelsPage />} />
                  <Route path="/goals" element={<GoalsPage />} />
                  <Route path="/tasks" element={<TasksPage />} />
                  <Route path="/providers" element={<ProvidersPage />} />
                  <Route path="/artifacts" element={<ArtifactsPage />} />
                  <Route path="/automation-rules" element={<AutomationRulesPage />} />
                  <Route path="/fs" element={<FileBrowserPage />} />
                  <Route path="/scheduler" element={<SchedulerPage />} />
                  <Route path="/security" element={<SecurityPage />} />
                  <Route path="/skills" element={<SkillsPage />} />
                  <Route path="/plugins" element={<PluginsPage />} />
                  <Route path="/runs" element={<RunsPage />} />
                  <Route path="/approvals" element={<ApprovalsPage />} />
                  <Route path="/settings" element={<SettingsPage />} />
                  <Route path="/voice" element={<VoiceSettingsPage />} />
                  <Route path="/memory" element={<MemoryPage />} />
                  <Route path="/users" element={<UsersPage />} />
                  <Route path="/profile" element={<ProfilePage />} />
                </Routes>
              </Suspense>
            </ErrorBoundary>
          </main>
        </div>
      </div>
      <ToastContainer />
      <CommandPalette />
      <InteractionModal />
    </div>
  )
}
