import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Save, Wifi, Server, Trash2, RefreshCw, Radio, Zap, Settings, Cpu, Volume2, BookOpen, Puzzle, Mail, Calendar, Unplug } from 'lucide-react'
import { useWsStore } from '../store/wsStore'
import { API_BASE, WS_URL, buildApiUrl, request } from '../api/client'
import { mutationError } from '../store/toastStore'
import { cn } from '../lib/utils'
import {
  Card,
  CardContent,
  Button,
  IconBox,
  SectionHeader,
  Badge,
} from '../components/ui/design'

const SETTINGS_KEY = 'aibrain_settings'

function loadSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY)
    if (raw) return JSON.parse(raw)
  } catch { /* ignore */ }
  return {}
}

function saveSettings(settings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
}

const quickLinks = [
  { to: '/channels', icon: Radio, label: 'Channels', desc: 'Telegram, Discord, Feishu, WeChat, WhatsApp', color: 'from-blue-500 to-indigo-600' },
  { to: '/providers', icon: Zap, label: 'Providers', desc: 'LLM, Image, Music models', color: 'from-amber-500 to-orange-600' },
  { to: '/voice', icon: Volume2, label: 'Voice', desc: 'Whisper speech-to-text models', color: 'from-emerald-500 to-teal-600' },
  { to: '/skills', icon: BookOpen, label: 'Skills', desc: 'Custom AI skill definitions', color: 'from-violet-500 to-purple-600' },
  { to: '/plugins', icon: Puzzle, label: 'Plugins', desc: 'Plugin management', color: 'from-pink-500 to-rose-600' },
  { to: '/users', icon: Cpu, label: 'Users', desc: 'Multi-user & proxy settings', color: 'from-cyan-500 to-blue-600' },
]

function GoogleConnectCard() {
  const queryClient = useQueryClient()

  const { data: status } = useQuery({
    queryKey: ['google-auth-status'],
    queryFn: () => request('/api/v1/auth/google/status'),
    refetchOnWindowFocus: true,
  })

  const disconnectMutation = useMutation({
    mutationFn: () => request('/api/v1/auth/google/disconnect', { method: 'POST' }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['google-auth-status'] }),
    onError: mutationError('Disconnect failed'),
  })

  const connected = status?.connected
  return (
    <Card variant="glass">
      <CardContent className="pt-6">
        <div className="flex items-start gap-3 mb-4">
          <IconBox icon={Mail} variant="success" size="sm" />
          <div className="flex-1">
            <h3 className="text-sm font-semibold text-text-primary mb-1">Google Account</h3>
            <p className="text-xs text-text-muted">Connect for Gmail and Calendar integration</p>
          </div>
          <Badge size="sm" variant={connected ? 'success' : 'default'}>
            {connected ? 'Connected' : 'Not connected'}
          </Badge>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 text-xs text-text-muted">
            <Mail className="w-3.5 h-3.5" />
            <span>Gmail</span>
            <Calendar className="w-3.5 h-3.5 ml-2" />
            <span>Calendar</span>
          </div>
          <div className="ml-auto flex gap-2">
            {connected ? (
              <Button variant="danger" size="sm" icon={Unplug}
                onClick={() => disconnectMutation.mutate()}
                disabled={disconnectMutation.isPending}>
                Disconnect
              </Button>
            ) : (
              <Button size="sm" icon={Zap}
                onClick={() => window.open(buildApiUrl('/api/v1/auth/google'), '_blank')}>
                Connect Google
              </Button>
            )}
          </div>
        </div>
        {connected && !status?.has_refresh_token && (
          <p className="text-[10px] text-amber-600 mt-2">
            No refresh token — reconnect with consent to enable offline access.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

export default function SettingsPage() {
  const navigate = useNavigate()
  const connected = useWsStore((s) => s.connected)
  const activeProvider = useWsStore((s) => s.activeProvider)
  const connect = useWsStore((s) => s.connect)

  const [settings, setSettings] = useState(loadSettings())
  const [saved, setSaved] = useState(false)

  function handleSave() {
    saveSettings(settings)
    setSaved(true)
    setTimeout(() => setSaved(false), 2000)
  }

  function handleClearData() {
    if (confirm('Clear all locally stored settings?')) {
      localStorage.removeItem(SETTINGS_KEY)
      setSettings({})
    }
  }

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-3xl mx-auto px-6 py-8">
        {/* Header with save button */}
        <div className="flex items-start justify-between mb-8">
          <SectionHeader
            title="Settings"
            description="System configuration and preferences"
            icon={Settings}
          />
          <Button size="md" icon={saved ? RefreshCw : Save} onClick={handleSave} className="mt-2">
            {saved ? 'Saved' : 'Save'}
          </Button>
        </div>

        <div className="space-y-6">
          {/* Connection */}
          <Card variant="glass">
            <CardContent className="pt-6">
              <div className="flex items-start gap-3 mb-4">
                <IconBox icon={Wifi} variant="accent" size="sm" />
                <div className="flex-1">
                  <h3 className="text-sm font-semibold text-text-primary mb-1">Connection</h3>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className={cn(
                  'w-2.5 h-2.5 rounded-full shadow-sm',
                  connected ? 'bg-gradient-to-br from-emerald-400 to-teal-500 shadow-emerald-500/30' : 'bg-gradient-to-br from-red-400 to-rose-500 shadow-red-500/30'
                )} />
                <span className="font-medium text-sm text-text-primary">
                  {connected ? 'Connected' : 'Disconnected'}
                </span>
                {!connected && (
                  <Button size="sm" variant="ghost" icon={RefreshCw} onClick={() => connect()}>
                    Reconnect
                  </Button>
                )}
              </div>
              {activeProvider && (
                <p className="text-xs text-text-muted mt-3 flex items-center gap-2">
                  Active provider:
                  <Badge size="sm" variant="primary">{activeProvider}</Badge>
                </p>
              )}
            </CardContent>
          </Card>

          {/* Google Account */}
          <GoogleConnectCard />

          {/* Quick Links */}
          <Card variant="glass">
            <CardContent className="pt-6">
              <div className="flex items-start gap-3 mb-4">
                <IconBox icon={Zap} variant="info" size="sm" />
                <div className="flex-1">
                  <h3 className="text-sm font-semibold text-text-primary mb-1">Configure Integrations</h3>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                {quickLinks.map((link) => (
                  <button
                    key={link.to}
                    onClick={() => navigate(link.to)}
                    className="group flex items-center gap-3 p-4 rounded-xl border border-gray-200 dark:border-gray-700/50 bg-white dark:bg-gray-800/30 hover:border-accent/30 hover:shadow-md hover:-translate-y-0.5 transition-all duration-200 text-left"
                  >
                    <div className={cn(
                      'p-2.5 rounded-xl shadow-sm transition-transform duration-200 group-hover:scale-105',
                      `bg-gradient-to-br ${link.color}`
                    )}>
                      <link.icon className="w-4 h-4 text-white" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-text-primary">{link.label}</p>
                      <p className="text-xs text-text-muted truncate">{link.desc}</p>
                    </div>
                  </button>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Server */}
          <Card variant="glass">
            <CardContent className="pt-6">
              <div className="flex items-start gap-3 mb-4">
                <IconBox icon={Server} variant="primary" size="sm" />
                <div className="flex-1">
                  <h3 className="text-sm font-semibold text-text-primary mb-1">Server</h3>
                </div>
              </div>
              <div className="space-y-3">
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">API URL</label>
                  <input value={API_BASE || '(default)'} readOnly
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm text-text-muted focus:outline-none focus:border-accent/50 transition-colors" />
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">WebSocket URL</label>
                  <input value={WS_URL || '(default)'} readOnly
                    className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm text-text-muted focus:outline-none focus:border-accent/50 transition-colors" />
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Data */}
          <Card variant="glass" className="border-red-200 dark:border-red-800/50 shadow-sm">
            <CardContent className="pt-6">
              <div className="flex items-start gap-3 mb-3">
                <IconBox icon={Trash2} variant="danger" size="sm" />
                <div className="flex-1">
                  <h3 className="text-sm font-semibold text-text-primary mb-1">Data</h3>
                  <p className="text-xs text-text-muted">Clear locally stored preferences.</p>
                </div>
              </div>
              <Button variant="danger" size="sm" icon={Trash2} onClick={handleClearData}>
                Clear Local Settings
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
