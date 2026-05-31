import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { channelsApi } from '../api/channels.api'
import { mutationError } from '../store/toastStore'
import {
  Plus, Pencil, Trash2, XCircle,
  AlertCircle, Power, PowerOff, RefreshCw,
  Send, Hash, Feather,
  Shield, EyeOff, Radio,
} from 'lucide-react'
import {
  Card,
  CardContent,
  Button,
  IconButton,
  IconBox,
  Badge,
  DotBadge,
  SectionHeader,
  Loading,
} from '../components/ui/design'

const PLATFORMS = {
  telegram: { Icon: Send, color: 'from-sky-500 to-blue-600', label: 'Telegram', fields: ['bot_token', 'chat_id'], desc: 'Create a bot via @BotFather to get a token' },
  discord:  { Icon: Hash, color: 'from-indigo-500 to-violet-600', label: 'Discord', fields: ['bot_token', 'application_id'], desc: 'Create an app in the Discord Developer Portal' },
  feishu:   { Icon: Feather, color: 'from-blue-500 to-cyan-600', label: 'Feishu', fields: ['app_id', 'app_secret', 'chat_id'], desc: 'Feishu Open Platform -> Create app' },
}

const FIELD_META = {
  bot_token:       { label: 'Bot Token', placeholder: '123456:ABC...', type: 'password' },
  application_id:  { label: 'Application ID', placeholder: '123456789...', type: 'text' },
  app_id:          { label: 'App ID', placeholder: 'cli_...', type: 'text' },
  app_secret:      { label: 'App Secret', placeholder: '••••••••', type: 'password' },
  chat_id:         { label: 'Chat ID', placeholder: '-100123456', type: 'text' },
}

function emptyForm(platform) {
  return {
    name: '',
    channel_type: platform || 'telegram',
    enabled: true,
    bot_token: '',
    chat_id: '',
    application_id: '',
    app_id: '',
    app_secret: '',
  }
}

export default function ChannelsPage() {
  const queryClient = useQueryClient()
  const [editingId, setEditingId] = useState(null)
  const [form, setForm] = useState(emptyForm())
  const [showForm, setShowForm] = useState(false)

  const { data, isLoading, isError } = useQuery({
    queryKey: ['channel-configs'],
    queryFn: () => channelsApi.list(),
  })

  const addMutation = useMutation({
    mutationFn: (body) => channelsApi.create(body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['channel-configs'] }); closeForm() },
    onError: mutationError('Add channel failed'),
  })
  const updateMutation = useMutation({
    mutationFn: ({ id, body }) => channelsApi.update(id, body),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['channel-configs'] }); closeForm() },
    onError: mutationError('Update channel failed'),
  })
  const deleteMutation = useMutation({
    mutationFn: (id) => channelsApi.remove(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['channel-configs'] }),
    onError: mutationError('Delete channel failed'),
  })

  const configs = data?.configs || []
  const pending = addMutation.isPending || updateMutation.isPending
  const error = addMutation.error || updateMutation.error

  function closeForm() { setShowForm(false); setEditingId(null); setForm(emptyForm()) }
  function openAdd(platform) { setEditingId('new'); setForm(emptyForm(platform)); setShowForm(true) }
  function openEdit(cfg) {
    setEditingId(cfg.id)
    setForm({
      name: cfg.name || '',
      channel_type: cfg.channel_type || 'telegram',
      enabled: !!cfg.enabled,
      bot_token: cfg.bot_token || '',
      chat_id: cfg.chat_id || '',
      application_id: cfg.application_id || '',
      app_id: cfg.app_id || '',
      app_secret: cfg.app_secret || '',
      webhook_secret: cfg.webhook_secret || '',
    })
    setShowForm(true)
  }

  function setField(field) { return (e) => setForm(f => ({ ...f, [field]: e.target.value })) }

  function handleSubmit(e) {
    e.preventDefault()
    const payload = {
      name: form.name || PLATFORMS[form.channel_type]?.label,
      channel_type: form.channel_type,
      enabled: form.enabled,
      bot_token: form.bot_token || undefined,
      chat_id: form.chat_id || undefined,
      application_id: form.application_id || undefined,
      app_id: form.app_id || undefined,
      app_secret: form.app_secret || undefined,
      webhook_secret: form.webhook_secret || undefined,
    }
    if (editingId === 'new') addMutation.mutate(payload)
    else updateMutation.mutate({ id: editingId, body: payload })
  }

  function toggleEnabled(cfg) {
    updateMutation.mutate({
      id: cfg.id,
      body: { channel_type: cfg.channel_type, enabled: !cfg.enabled },
    })
  }

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-6xl mx-auto px-6 py-8">
        {/* Header */}
        <div className="flex items-start justify-between mb-8">
          <SectionHeader title="Channels" description="Manage messaging platform connections" icon={Radio} />
          <IconButton icon={RefreshCw} variant="ghost" size="md" onClick={() => queryClient.invalidateQueries({ queryKey: ['channel-configs'] })} title="Refresh" />
        </div>

        {/* Add/Edit Form Modal */}
        {showForm && (
          <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50" onClick={closeForm}>
            <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-hidden border border-gray-200 dark:border-gray-800" onClick={e => e.stopPropagation()}>
              <div className="p-5 border-b border-gray-100 dark:border-gray-800 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <IconBox
                    icon={PLATFORMS[form.channel_type]?.Icon || Shield}
                    variant="custom"
                    size="sm"
                    className={`bg-gradient-to-br ${PLATFORMS[form.channel_type]?.color || 'from-gray-400 to-gray-500'}`}
                  />
                  <div>
                    <h2 className="text-sm font-semibold text-text-primary">
                      {editingId === 'new' ? 'New Connection' : 'Edit Connection'}
                    </h2>
                    <p className="text-xs text-text-muted">{PLATFORMS[form.channel_type]?.label || ''}</p>
                  </div>
                </div>
                <IconButton icon={XCircle} onClick={closeForm} />
              </div>

              <div className="p-5 overflow-y-auto max-h-[70vh]">
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div className="grid grid-cols-3 gap-4">
                    <div>
                      <label className="block text-xs font-medium text-text-secondary mb-1.5">Platform</label>
                      <select value={form.channel_type} onChange={setField('channel_type')} disabled={editingId !== 'new'}
                        className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors disabled:opacity-60">
                        {Object.entries(PLATFORMS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                      </select>
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-text-secondary mb-1.5">Display Name</label>
                      <input value={form.name} onChange={setField('name')} placeholder={PLATFORMS[form.channel_type]?.label}
                        className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm focus:outline-none focus:border-accent/50 transition-colors" />
                    </div>
                    <div className="flex items-end">
                      <label className="flex items-center gap-2 cursor-pointer">
                        <div className={`relative w-9 h-5 rounded-full transition-colors ${form.enabled ? 'bg-accent' : 'bg-gray-200 dark:bg-gray-700'}`}>
                          <div className={`absolute top-0.5 w-4 h-4 rounded-full bg-white shadow transition-transform ${form.enabled ? 'translate-x-4' : 'translate-x-0.5'}`} />
                        </div>
                        <input type="checkbox" checked={!!form.enabled} onChange={e => setForm(f => ({ ...f, enabled: e.target.checked }))} className="sr-only" />
                        <span className="text-xs text-text-secondary">{form.enabled ? 'Enabled' : 'Disabled'}</span>
                      </label>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    {PLATFORMS[form.channel_type]?.fields.map(field => (
                      <div key={field}>
                        <label className="block text-xs font-medium text-text-secondary mb-1.5">{FIELD_META[field]?.label || field}</label>
                        <input
                          value={form[field] || ''}
                          onChange={setField(field)}
                          type={FIELD_META[field]?.type || 'text'}
                          placeholder={FIELD_META[field]?.placeholder || field}
                          className="w-full rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-3.5 py-2.5 text-sm font-mono focus:outline-none focus:border-accent/50 transition-colors"
                        />
                      </div>
                    ))}
                  </div>

                  {error && <p className="text-xs text-red-500">{error.message || 'Failed'}</p>}

                  <div className="flex items-center gap-3 pt-2">
                    <Button type="submit" disabled={pending}>
                      {pending ? 'Saving...' : editingId === 'new' ? 'Create Connection' : 'Save Changes'}
                    </Button>
                    <Button type="button" variant="secondary" onClick={closeForm}>Cancel</Button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        )}

        {/* Platform sections */}
        <div className="space-y-6">
          {Object.entries(PLATFORMS).map(([key, plat]) => {
            const platformConfigs = configs.filter(c => c.channel_type === key)
            return (
              <Card key={key} variant="glass" className="overflow-hidden">
                <CardContent className="pt-6">
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <IconBox
                        icon={plat.Icon}
                        variant="custom"
                        size="sm"
                        className={`bg-gradient-to-br ${plat.color}`}
                      />
                      <div>
                        <h3 className="text-sm font-semibold text-text-primary">{plat.label}</h3>
                        <p className="text-xs text-text-muted">{plat.desc}</p>
                      </div>
                      <Badge size="sm" variant="default">{platformConfigs.length} connection{platformConfigs.length !== 1 ? 's' : ''}</Badge>
                    </div>
                    <Button size="sm" icon={Plus} onClick={() => openAdd(key)}>Add</Button>
                  </div>

                  {platformConfigs.length === 0 ? (
                    <div className="rounded-xl border border-dashed border-card-border p-8 flex items-center justify-between bg-white/50 dark:bg-gray-800/30">
                      <div className="flex items-center gap-3">
                        <div className="p-2 rounded-xl bg-gray-100 dark:bg-gray-800">
                          <EyeOff className="w-4 h-4 text-text-muted" />
                        </div>
                        <span className="text-sm text-text-muted">No {plat.label} connection</span>
                      </div>
                      <Button size="sm" onClick={() => openAdd(key)}>Add {plat.label}</Button>
                    </div>
                  ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                      {platformConfigs.map(cfg => (
                        <div key={cfg.id}
                          className="group relative overflow-hidden rounded-xl border border-gray-200 dark:border-gray-700/50 bg-white dark:bg-gray-800/30 p-4 hover:border-accent/30 hover:shadow-md transition-all duration-200"
                        >
                          <div className="flex items-start justify-between mb-3">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <p className="text-sm font-semibold text-text-primary truncate">{cfg.name || plat.label}</p>
                                {cfg.enabled
                                  ? <DotBadge color="emerald" />
                                  : <DotBadge color="gray" />
                                }
                              </div>
                              <p className="text-xs text-text-muted mt-0.5 font-mono">{cfg.id?.slice(0, 8)}</p>
                            </div>
                            <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-all duration-200">
                              <IconButton
                                icon={cfg.enabled ? PowerOff : Power}
                                variant="ghost"
                                size="sm"
                                onClick={() => toggleEnabled(cfg)}
                                title={cfg.enabled ? 'Disable' : 'Enable'}
                              />
                              <IconButton icon={Pencil} variant="ghost" size="sm" onClick={() => openEdit(cfg)} />
                              <IconButton icon={Trash2} variant="danger" size="sm" onClick={() => { if (confirm('Delete this connection?')) deleteMutation.mutate(cfg.id) }} />
                            </div>
                          </div>
                          {cfg.enabled ? (
                            <Badge size="sm" variant="success">Active</Badge>
                          ) : (
                            <Badge size="sm" variant="default">Disabled</Badge>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>
            )
          })}
        </div>

        {isLoading && <Loading text="Loading channels..." />}
        {isError && (
          <div className="flex items-center justify-center py-16 gap-2">
            <AlertCircle className="w-4 h-4 text-red-500" />
            <span className="text-sm text-red-500">Failed to load channels</span>
          </div>
        )}
      </div>
    </div>
  )
}
