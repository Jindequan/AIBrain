import { useState, useEffect, useMemo } from 'react'
import {
  Brain, Eye, EyeOff, KeyRound, Plus, RefreshCw, Search,
  Server, Star, Trash2,
} from 'lucide-react'
import { modelSettingsApi } from '../api/modelSettings'
import { cn } from '../lib/utils'
import { Button, IconButton } from '../components/ui/design'
import { useToastStore } from '../store/toastStore'

function formatTokens(n) {
  if (n == null) return ''
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(1)}B`
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return n.toLocaleString()
}

function statusColor(p) {
  if (p.enabled && p.has_key) return 'bg-green-400'
  if (p.has_key && !p.enabled) return 'bg-gray-300 dark:bg-gray-600'
  return 'bg-amber-400'
}

const FIELD_CLASS = 'w-full rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-950 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:border-blue-400/50'

export default function ProvidersPage() {
  const { addToast } = useToastStore()
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  const [modelSearch, setModelSearch] = useState('')
  const [selectedId, setSelectedId] = useState('')
  const [keyInputs, setKeyInputs] = useState({})
  const [showKey, setShowKey] = useState({})
  const [baseUrlDraft, setBaseUrlDraft] = useState({})
  const [pendingOps, setPendingOps] = useState(new Set())
  const [showAddCustom, setShowAddCustom] = useState(false)
  const [customName, setCustomName] = useState('')
  const [customBaseUrl, setCustomBaseUrl] = useState('')
  const [customKey, setCustomKey] = useState('')

  const load = async (signal) => {
    try {
      setLoading(true)
      const d = await modelSettingsApi.get(signal)
      setData(d)
    } catch (err) {
      if (err?.name !== 'AbortError') setError(err?.message || 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    const ctrl = new AbortController()
    load(ctrl.signal)
    return () => ctrl.abort()
  }, [])

  const setOp = (id, v) => {
    setPendingOps(p => { const n = new Set(p); if (v) n.add(id); else n.delete(id); return n })
  }

  const providers = useMemo(() => {
    if (!data) return []
    const q = search.toLowerCase()
    return data.providers.filter(p => {
      const t = `${p.id} ${p.name}`.toLowerCase()
      return t.includes(q)
    })
  }, [data, search])

  const selected = data?.providers.find(p => p.id === selectedId) || null

  const [providerModels, setProviderModels] = useState([])
  const [modelsLoading, setModelsLoading] = useState(false)

  // Load models lazily when a provider is selected
  const [modelsError, setModelsError] = useState(null)
  useEffect(() => {
    if (!selected?.id) { setProviderModels([]); setModelsError(null); return }
    let cancelled = false
    setModelsLoading(true)
    setModelsError(null)
    modelSettingsApi.fetchProviderModels(selected.id)
      .then(res => { if (!cancelled) { setProviderModels(res.models || []); if (res.models?.length === 0) setModelsError('No models found for this provider. If this is a custom provider, models must be added manually.') } })
      .catch(err => { if (!cancelled) { setProviderModels([]); setModelsError(err?.message || 'Failed to load models') } })
      .finally(() => { if (!cancelled) setModelsLoading(false) })
    return () => { cancelled = true }
  }, [selected?.id])

  const filteredModels = useMemo(() => {
    const q = modelSearch.toLowerCase()
    return providerModels.filter(m => {
      if (!q) return true
      return `${m.id} ${m.name} ${m.description}`.toLowerCase().includes(q)
    })
  }, [data, selected, modelSearch])

  // ── Actions ──

  const handleToggleProvider = async (p) => {
    const opId = `tgl-${p.id}`
    const willBeEnabled = !p.enabled
    if (willBeEnabled && !p.has_key) {
      addToast({ title: 'No API key', message: `Enter an API key for ${p.name} before enabling.`, variant: 'warning' })
      return
    }
    setOp(opId, true)
    try {
      const result = await modelSettingsApi.configureProvider({
        name: p.id, enabled: willBeEnabled,
        base_url: baseUrlDraft[p.id] ?? p.base_url,
        custom: p.custom, provider_type: p.provider_type,
      })
      setData(result)
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleSaveKey = async (providerId, apiKey) => {
    if (!apiKey.trim()) return
    const opId = `key-${providerId}`
    setOp(opId, true)
    try {
      const result = await modelSettingsApi.storeCredential(providerId, apiKey)
      setData(result)
      setKeyInputs(p => ({ ...p, [providerId]: '' }))
      addToast({ title: 'Key saved', message: `API key for ${providerId} stored`, variant: 'success' })
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed to save key', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleDeleteProvider = async (providerId) => {
    if (!window.confirm(`Remove provider "${providerId}"? This clears the stored key and disables it.`)) return
    const opId = `del-${providerId}`
    setOp(opId, true)
    try {
      const result = await modelSettingsApi.deleteProvider(providerId)
      setData(result)
      if (selectedId === providerId) setSelectedId('')
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed to delete', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleToggleModel = async (modelId) => {
    if (!data || !selected) return
    const opId = `mdl-${modelId}`
    const fullModelId = `${selected.id}:${modelId}`

    // Check current enabled state: model is enabled if NOT in disabled_models
    const currentlyEnabled = !(data.disabled_models || []).includes(fullModelId)

    // Guard: don't disable the last enabled model unless user confirms
    if (currentlyEnabled) {
      const totalEnabled = providerModels.length - (data.disabled_models || []).filter(d => d.startsWith(selected.id + ':')).length
      if (totalEnabled <= 1) {
        if (!window.confirm('This is the last enabled model. Disabling it will leave no model available. Continue?')) return
      }
    }

    setOp(opId, true)
    try {
      const effectiveDefault = data.default_model === modelId && currentlyEnabled
        ? null  // unset default if we're disabling the default model
        : data.default_model

      const result = await modelSettingsApi.toggleModel(fullModelId, !currentlyEnabled, effectiveDefault)
      setData(result)
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleSetDefaultModel = async (modelId) => {
    if (!data) return
    const opId = `def-${modelId}`
    setOp(opId, true)
    try {
      const result = await modelSettingsApi.updateModelPolicy({ default_model: modelId })
      setData(result)
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleRefreshCatalog = async () => {
    setOp('catalog', true)
    try {
      const result = await modelSettingsApi.refreshCatalog()
      setData(result)
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed to sync', variant: 'error' })
    } finally { setOp('catalog', false) }
  }

  const handleAddCustom = async () => {
    if (!customName.trim()) return
    const opId = 'add-custom'
    setOp(opId, true)
    try {
      let result = await modelSettingsApi.configureProvider({
        name: customName.trim(), enabled: true,
        base_url: customBaseUrl.trim() || undefined,
        custom: true, provider_type: 'openai',
      })
      if (customKey.trim()) {
        result = await modelSettingsApi.storeCredential(customName.trim(), customKey.trim())
      }
      setData(result)
      setSelectedId(customName.trim())
      setShowAddCustom(false)
      setCustomName('')
      setCustomBaseUrl('')
      setCustomKey('')
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed to add', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  const handleSaveBaseUrl = async (providerId, baseUrl) => {
    if (!data) return
    const opId = `url-${providerId}`
    setOp(opId, true)
    try {
      const p = data.providers.find(x => x.id === providerId)
      const result = await modelSettingsApi.configureProvider({
        name: providerId,
        enabled: p?.enabled ?? true,
        base_url: baseUrl || undefined,
        custom: p?.custom ?? false,
        provider_type: p?.provider_type ?? 'openai',
      })
      setData(result)
    } catch (err) {
      addToast({ title: 'Error', message: err?.message || 'Failed to save', variant: 'error' })
    } finally { setOp(opId, false) }
  }

  // ── Render ──

  if (loading) return <div className="flex items-center justify-center h-64 text-sm text-gray-400">Loading...</div>
  if (error && !data) return <div className="flex items-center justify-center h-64 text-sm text-red-500">{error}</div>
  if (!data) return null

  return (
    <div className="flex flex-col h-full">
      {/* Sync loading overlay */}
      {pendingOps.has('catalog') && (
        <div className="absolute inset-0 z-50 bg-white/60 dark:bg-gray-950/60 flex items-center justify-center">
          <div className="flex flex-col items-center gap-3">
            <RefreshCw className="w-8 h-8 animate-spin text-blue-500" />
            <p className="text-sm text-gray-600 dark:text-gray-400">Syncing model catalog...</p>
          </div>
        </div>
      )}
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-800">
        <div>
          <h1 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Providers & Models</h1>
          <p className="text-xs text-gray-500 mt-0.5">
            {data.catalog.provider_count} providers · {data.catalog.model_count} models from LLMDB
          </p>
        </div>
        <div className="flex items-center gap-2">
          {data.setup_required && (
            <span className="text-xs text-amber-600 bg-amber-50 dark:bg-amber-900/20 px-2 py-1 rounded-full font-medium">
              Setup required — configure a provider to get started
            </span>
          )}
          <Button variant="secondary" icon={RefreshCw} onClick={handleRefreshCatalog} disabled={pendingOps.has('catalog')}>
            {pendingOps.has('catalog') ? 'Syncing...' : 'Sync'}
          </Button>
          <Button variant="primary" icon={Plus} onClick={() => setShowAddCustom(true)}>
            Custom
          </Button>
        </div>
      </div>

      <div className="flex flex-1 overflow-hidden">
        {/* Left: Provider list */}
        <div className="w-72 border-r border-gray-200 dark:border-gray-800 flex flex-col shrink-0">
          <div className="p-3">
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" />
              <input
                value={search}
                onChange={e => setSearch(e.target.value)}
                placeholder="Search providers..."
                className={cn(FIELD_CLASS, 'pl-8 text-xs')}
              />
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">
            {providers.map(p => (
              <button
                key={p.id}
                onClick={() => setSelectedId(p.id)}
                className={cn(
                  'w-full flex items-center gap-3 px-4 py-3 text-left transition-colors border-b border-gray-100 dark:border-gray-800/50',
                  selected?.id === p.id
                    ? 'bg-blue-50 dark:bg-blue-900/10'
                    : 'hover:bg-gray-50 dark:hover:bg-gray-900/50'
                )}
              >
                <span className={cn('w-2 h-2 rounded-full shrink-0', statusColor(p))} />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">{p.name}</div>
                  <div className="text-[11px] text-gray-500 truncate">
                    {p.env_key ? <span className="text-gray-400">env: {p.env_key}</span> : p.custom ? 'Custom' : p.id}
                  </div>
                </div>
                {pendingOps.has(`tgl-${p.id}`) || pendingOps.has(`key-${p.id}`) || pendingOps.has(`del-${p.id}`) ? (
                  <RefreshCw className="w-3 h-3 animate-spin text-gray-400" />
                ) : null}
              </button>
            ))}
            {providers.length === 0 && (
              <div className="px-4 py-8 text-center text-xs text-gray-400">No providers found</div>
            )}
          </div>
        </div>

        {/* Right: Provider detail + model list */}
        <div className="flex-1 overflow-y-auto">
          {!selected ? (
            <div className="flex items-center justify-center h-full text-sm text-gray-400">
              Select a provider from the list
            </div>
          ) : (
            <div className="max-w-2xl mx-auto p-6 space-y-8">
              {/* Provider header */}
              <div className="flex items-start justify-between">
                <div>
                  <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100">{selected.name}</h2>
                  <p className="text-xs text-gray-500 mt-1">
                    {selected.custom ? 'Custom provider' : `Catalog provider · ${selected.id}`}
                    {selected.env_key ? ` · env: ${selected.env_key}` : ''}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <label className="relative inline-flex cursor-pointer items-center">
                    <input
                      type="checkbox"
                      checked={selected.enabled}
                      onChange={() => handleToggleProvider(selected)}
                      disabled={!selected.has_key || pendingOps.has(`tgl-${selected.id}`)}
                      className="peer sr-only"
                    />
                    <span className={cn(
                      'h-6 w-11 rounded-full transition-colors',
                      selected.enabled ? 'bg-blue-500' : 'bg-gray-300 dark:bg-gray-700'
                    )} />
                    <span className="absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white transition-transform peer-checked:translate-x-5" />
                  </label>
                  <IconButton
                    icon={Trash2}
                    variant="danger"
                    onClick={() => handleDeleteProvider(selected.id)}
                    disabled={pendingOps.has(`del-${selected.id}`)}
                  />
                </div>
              </div>

              {/* API Key section */}
              <section className="space-y-3">
                <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
                  <KeyRound className="w-4 h-4" /> API Key
                </h3>
                {selected.has_key ? (
                  <div className="flex items-center gap-2 text-sm text-green-600">
                    <span className="w-2 h-2 rounded-full bg-green-400" />
                    Key configured
                    <span className="text-xs text-gray-400">
                      (set via env or previously saved)
                    </span>
                  </div>
                ) : (
                  <div className="text-xs text-amber-600">No API key configured</div>
                )}
                <div className="flex gap-2">
                  <div className="relative flex-1">
                    <input
                      type={showKey[selected.id] ? 'text' : 'password'}
                      value={keyInputs[selected.id] ?? ''}
                      onChange={e => setKeyInputs(p => ({ ...p, [selected.id]: e.target.value }))}
                      onKeyDown={e => { if (e.key === 'Enter') handleSaveKey(selected.id, keyInputs[selected.id] || '') }}
                      placeholder={selected.env_key ? `Or set env: ${selected.env_key}` : 'Enter API key...'}
                      className={cn(FIELD_CLASS, 'font-mono text-xs pr-10')}
                    />
                    <button
                      type="button"
                      onClick={() => setShowKey(p => ({ ...p, [selected.id]: !p[selected.id] }))}
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
                    >
                      {showKey[selected.id] ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                  <Button
                    variant="primary"
                    disabled={!keyInputs[selected.id]?.trim() || pendingOps.has(`key-${selected.id}`)}
                    onClick={() => handleSaveKey(selected.id, keyInputs[selected.id] || '')}
                  >
                    Save
                  </Button>
                </div>
              </section>

              {/* Base URL section */}
              <section className="space-y-3">
                <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
                  <Server className="w-4 h-4" /> Base URL
                </h3>
                <div className="flex gap-2">
                  <input
                    value={baseUrlDraft[selected.id] ?? selected.base_url ?? ''}
                    onChange={e => setBaseUrlDraft(p => ({ ...p, [selected.id]: e.target.value }))}
                    onKeyDown={e => { if (e.key === 'Enter') handleSaveBaseUrl(selected.id, baseUrlDraft[selected.id] || selected.base_url || '') }}
                    placeholder={selected.custom ? 'https://api.example.com/v1' : 'Auto-detected by ReqLLM'}
                    disabled={!selected.custom}
                    className={cn(FIELD_CLASS, 'font-mono text-xs', !selected.custom && 'bg-gray-50 text-gray-400 cursor-not-allowed')}
                  />
                  {selected.custom && (
                    <Button
                      variant="secondary"
                      disabled={pendingOps.has(`url-${selected.id}`)}
                      onClick={() => handleSaveBaseUrl(selected.id, baseUrlDraft[selected.id] || '')}
                    >
                      Save
                    </Button>
                  )}
                </div>
              </section>

              {/* Models section */}
              <section className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
                    <Brain className="w-4 h-4" /> Models
                    <span className="text-xs text-gray-400 font-normal">
                      ({modelsLoading ? '...' : providerModels.length})
                    </span>
                  </h3>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => {
                        setModelsLoading(true)
                        modelSettingsApi.fetchProviderModels(selected.id)
                          .then(res => setProviderModels(res.models || []))
                          .catch(() => setProviderModels([]))
                          .finally(() => setModelsLoading(false))
                      }}
                      disabled={modelsLoading}
                      className="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 flex items-center gap-1"
                      title="Refresh model list for this provider"
                    >
                      <RefreshCw className={cn('w-3 h-3', modelsLoading && 'animate-spin')} />
                      Refresh
                    </button>
                    <div className="relative">
                      <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-400" />
                      <input
                        value={modelSearch}
                        onChange={e => setModelSearch(e.target.value)}
                        placeholder="Filter models..."
                      className={cn(FIELD_CLASS, 'pl-8 text-xs w-48')}
                    />
                  </div>
                </div>
                </div>

                <div className="space-y-1">
                  {filteredModels.map(m => {
                    const isDefault = m.id === data.default_model
                    const isEnabled = m.enabled
                    const isLoading = pendingOps.has(`mdl-${m.id}`) || pendingOps.has(`def-${m.id}`)

                    return (
                      <div
                        key={m.id}
                        className={cn(
                          'flex items-center gap-3 px-3 py-2 rounded-lg transition-colors',
                          isEnabled ? 'bg-white dark:bg-gray-900' : 'bg-gray-50 dark:bg-gray-900/50 opacity-60'
                        )}
                      >
                        <label className="relative inline-flex cursor-pointer items-center shrink-0">
                          <input
                            type="checkbox"
                            checked={isEnabled}
                            onChange={() => handleToggleModel(m.id)}
                            disabled={isLoading}
                            className="peer sr-only"
                          />
                          <span className={cn(
                            'h-5 w-9 rounded-full transition-colors',
                            isEnabled ? 'bg-blue-500' : 'bg-gray-300 dark:bg-gray-700'
                          )} />
                          <span className="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white transition-transform peer-checked:translate-x-4" />
                        </label>

                        <button
                          onClick={() => handleSetDefaultModel(m.id)}
                          disabled={!isEnabled || isLoading}
                          className="shrink-0"
                          title={isDefault ? 'Default model' : 'Set as default'}
                        >
                          <Star className={cn(
                            'w-4 h-4 transition-colors',
                            isDefault ? 'fill-amber-400 text-amber-400' : 'text-gray-300 hover:text-amber-400'
                          )} />
                        </button>

                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                              {m.name}
                            </span>
                            {isDefault && (
                              <span className="text-[10px] bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 px-1.5 py-0.5 rounded font-medium">
                                default
                              </span>
                            )}
                          </div>
                          <div className="flex items-center gap-2 text-[11px] text-gray-500 mt-0.5">
                            {m.context_length != null && <span>ctx: {formatTokens(m.context_length)}</span>}
                            {m.max_output_tokens != null && <span>out: {formatTokens(m.max_output_tokens)}</span>}
                            {m.input_modalities.filter(t => t !== 'text').map(t => (
                              <span key={t} className="capitalize">{t}</span>
                            ))}
                          </div>
                        </div>

                        {isLoading && <RefreshCw className="w-3 h-3 animate-spin text-gray-400 shrink-0" />}
                      </div>
                    )
                  })}
                  {filteredModels.length === 0 && !modelsLoading && (
                    <div className="text-center py-6 text-xs text-gray-400">
                      {modelsError || (modelSearch ? 'No models match your search' : 'No models found for this provider')}
                    </div>
                  )}
                </div>
              </section>
            </div>
          )}
        </div>
      </div>

      {/* Add Custom Provider Modal */}
      {showAddCustom && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30" onClick={() => setShowAddCustom(false)}>
          <div className="bg-white dark:bg-gray-900 rounded-2xl shadow-xl p-6 w-full max-w-md space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Add Custom Provider</h2>
            <p className="text-xs text-gray-500">For OpenAI-compatible APIs (Ollama, vLLM, local models, etc.)</p>
            <input
              value={customName}
              onChange={e => setCustomName(e.target.value)}
              placeholder="Provider name (e.g., my-llama)"
              className={FIELD_CLASS}
              autoFocus
            />
            <input
              value={customBaseUrl}
              onChange={e => setCustomBaseUrl(e.target.value)}
              placeholder="Base URL (e.g., http://localhost:11434/v1)"
              className={cn(FIELD_CLASS, 'font-mono text-xs')}
            />
            <input
              type="password"
              value={customKey}
              onChange={e => setCustomKey(e.target.value)}
              placeholder="API key (optional)"
              className={cn(FIELD_CLASS, 'font-mono text-xs')}
            />
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="secondary" onClick={() => setShowAddCustom(false)}>Cancel</Button>
              <Button variant="primary" onClick={handleAddCustom} disabled={!customName.trim() || pendingOps.has('add-custom')}>
                {pendingOps.has('add-custom') ? 'Adding...' : 'Add Provider'}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
