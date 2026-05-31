import { useState, useEffect, useCallback } from 'react'
import { Cpu, Download, Trash2, Loader, Globe, Zap, Sparkles } from 'lucide-react'
import { cn } from '../lib/utils'
import { buildApiUrl } from '../api/client'
import {
  Card,
  CardContent,
  Button,
  IconButton,
  Badge,
  DotBadge,
  IconBox,
  GradientIconBox,
  SectionHeader,
  SectionTitle,
  BackButton,
  StatusCard,
  Loading,
} from '../components/ui/design'

const MODEL_INFO = {
  tiny:       { label: 'Tiny',       size: '75MB',  desc: 'Fastest, multilingual', color: 'from-gray-400 to-gray-500' },
  'tiny.en':  { label: 'Tiny (EN)',  size: '75MB',  desc: 'English only, fastest', color: 'from-blue-400 to-blue-500' },
  base:       { label: 'Base',       size: '150MB', desc: 'Recommended! Fast, multilingual', color: 'from-emerald-400 to-teal-500' },
  'base.en':  { label: 'Base (EN)',  size: '150MB', desc: 'English only, fast', color: 'from-blue-400 to-blue-500' },
  small:      { label: 'Small',      size: '500MB', desc: 'Slower, good quality, multilingual', color: 'from-violet-400 to-purple-500' },
  'small.en': { label: 'Small (EN)', size: '500MB', desc: 'English only, slower', color: 'from-blue-400 to-blue-500' },
  medium:     { label: 'Medium',     size: '1.5GB', desc: 'Slow, great quality, multilingual', color: 'from-orange-400 to-red-500' },
  turbo:      { label: 'Turbo',      size: '1.6GB', desc: 'Fast, near-large quality, multilingual', color: 'from-pink-400 to-rose-500' },
  large:      { label: 'Large',      size: '3.1GB', desc: 'Slowest, best quality, multilingual', color: 'from-amber-400 to-yellow-500' },
}

function getActiveModel() {
  return localStorage.getItem('voice_active_model') || null
}

function setActiveModel(name) {
  if (name) {
    localStorage.setItem('voice_active_model', name)
  } else {
    localStorage.removeItem('voice_active_model')
  }
}

function getLanguagePreference() {
  return localStorage.getItem('voice_language') || 'auto'
}

function setLanguagePreference(lang) {
  localStorage.setItem('voice_language', lang)
}

export default function VoiceSettingsPage() {
  const [models, setModels] = useState([])
  const [activeModel, setActiveModelState] = useState(getActiveModel)
  const [language, setLanguage] = useState(getLanguagePreference)
  const [downloading, setDownloading] = useState(null)
  const [loading, setLoading] = useState(true)

  const refreshModels = useCallback(async () => {
    try {
      const res = await fetch(buildApiUrl('/api/v1/stt/models'))
      if (!res.ok) throw new Error(`Failed to load STT models: ${res.status}`)
      const data = await res.json()
      if (data.models) setModels(data.models)
    } catch { /* ignore transient model-list failures */ }
    setLoading(false)
  }, [])

  useEffect(() => {
    const id = setTimeout(refreshModels, 0)
    return () => clearTimeout(id)
  }, [refreshModels])

  const handleDownload = useCallback(async (name) => {
    setDownloading(name)
    try {
      const modelName = encodeURIComponent(name)
      const res = await fetch(buildApiUrl(`/api/v1/stt/models/${modelName}/download`), { method: 'POST' })
      if (!res.ok) throw new Error(`Failed to download STT model: ${res.status}`)
      await refreshModels()
    } catch { /* ignore transient download failures */ }
    setDownloading(null)
  }, [refreshModels])

  const handleDelete = useCallback(async (name) => {
    const modelName = encodeURIComponent(name)
    const res = await fetch(buildApiUrl(`/api/v1/stt/models/${modelName}`), { method: 'DELETE' })
    if (!res.ok) return
    if (activeModel === name) {
      setActiveModel(null)
      setActiveModelState(null)
    }
    await refreshModels()
  }, [activeModel, refreshModels])

  const handleActivate = useCallback((name) => {
    setActiveModel(name)
    setActiveModelState(name)
  }, [])

  return (
    <div className="min-h-full bg-gradient-to-br from-gray-50 via-white to-blue-50/30 dark:from-gray-900 dark:via-gray-900 dark:to-blue-950/20">
      <div className="max-w-3xl mx-auto px-6 py-8">
        <BackButton to="/settings" />

        <SectionHeader
          title="Voice Settings"
          description="Download and configure Whisper models for voice input"
          icon={Cpu}
        />

        {/* Language preference card */}
        <Card variant="glass" className="mb-6">
          <CardContent className="pt-6">
            <div className="flex items-start gap-3 mb-4">
              <IconBox icon={Globe} variant="info" size="sm" />
              <div className="flex-1">
                <h3 className="text-sm font-semibold text-text-primary mb-1">Language Preference</h3>
                <p className="text-xs text-text-muted">Choosing your primary language improves accuracy for mixed input</p>
              </div>
            </div>
            <div className="flex gap-2">
              {[
                { value: 'auto', label: 'Auto Detect', icon: Zap },
                { value: 'zh', label: 'Chinese First', icon: '🇨🇳' },
                { value: 'en', label: 'English First', icon: '🇬🇧' },
              ].map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    setLanguage(opt.value)
                    setLanguagePreference(opt.value)
                  }}
                  className={cn(
                    'flex-1 px-4 py-2.5 text-xs font-medium rounded-xl border transition-all duration-200 flex items-center justify-center gap-1.5',
                    language === opt.value
                      ? 'bg-gradient-to-r from-accent to-accent-hover text-white border-transparent shadow-md shadow-accent/20'
                      : 'bg-white dark:bg-gray-800 text-text-secondary border-gray-200 dark:border-gray-700 hover:border-accent/30 hover:bg-accent/5'
                  )}
                >
                  {typeof opt.icon === 'string' ? <span className="text-sm">{opt.icon}</span> : <opt.icon className="w-3.5 h-3.5" />}
                  {opt.label}
                </button>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Active model indicator */}
        <StatusCard
          status={activeModel ? 'success' : 'warning'}
          title={activeModel ? 'Active Model' : 'No model activated'}
          value={activeModel}
          badge={activeModel && MODEL_INFO[activeModel]?.size}
          description={activeModel ? 'This model will be used for speech recognition in Chat' : 'Download and activate a model to enable voice input'}
          className="mb-6"
        />

        {/* Model list */}
        <SectionTitle
          title="Available Models"
          count={{ current: models.filter(m => m.installed).length, total: models.length }}
        />

        {loading ? (
          <Loading text="Loading models..." />
        ) : (
          <div className="space-y-3">
            {models.map((m) => {
              const info = MODEL_INFO[m.name]
              const isActive = m.name === activeModel
              return (
                <div
                  key={m.name}
                  className={cn(
                    'group relative overflow-hidden rounded-2xl border transition-all duration-200',
                    isActive
                      ? 'bg-gradient-to-r from-accent/5 to-accent-hover/5 border-accent/40 shadow-md shadow-accent/10'
                      : 'bg-white dark:bg-gray-800/50 border-gray-200 dark:border-gray-700/50 hover:border-accent/30 hover:shadow-md'
                  )}
                >
                  {/* Gradient accent bar */}
                  <div className={cn(
                    'absolute left-0 top-0 bottom-0 w-1 transition-opacity duration-200 bg-gradient-to-b',
                    isActive ? 'opacity-100' : 'opacity-0 group-hover:opacity-60',
                    info?.color || 'from-gray-400 to-gray-500'
                  )} />

                  <div className="flex items-center gap-4 px-5 py-4">
                    {/* Model icon */}
                    <GradientIconBox
                      icon={Cpu}
                      gradient={isActive ? 'from-accent to-accent-hover' : (info?.color || 'from-gray-400 to-gray-500')}
                      size="md"
                    />

                    {/* Model info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className={cn(
                          'font-semibold text-sm',
                          isActive ? 'text-accent' : 'text-text-primary'
                        )}>
                          {info?.label || m.name}
                        </span>
                        <Badge size="sm" variant="default">{info?.size || '?'}</Badge>
                        {isActive && <Badge size="sm" variant="gradient">Active</Badge>}
                      </div>
                      <p className="text-xs text-text-secondary/80 mb-1.5">{info?.desc || ''}</p>
                      <div className="flex items-center gap-2">
                        {!m.name.endsWith('.en') && (
                          <Badge size="sm" variant="info" icon={Globe}>Multilingual</Badge>
                        )}
                        {m.name === 'base' && (
                          <Badge size="sm" variant="success" icon={Sparkles}>Recommended</Badge>
                        )}
                      </div>
                    </div>

                    {/* Status / actions */}
                    <div className="flex items-center gap-3 shrink-0">
                      <DotBadge color={m.installed ? 'emerald' : 'gray'} />

                      {m.installed ? (
                        <>
                          {!isActive && (
                            <Button size="sm" onClick={() => handleActivate(m.name)}>
                              Activate
                            </Button>
                          )}
                          <IconButton
                            icon={Trash2}
                            variant="danger"
                            size="sm"
                            onClick={() => handleDelete(m.name)}
                            title="Delete this model"
                          />
                        </>
                      ) : (
                        <Button
                          size="sm"
                          variant="secondary"
                          icon={downloading === m.name ? Loader : Download}
                          disabled={downloading === m.name}
                          onClick={() => handleDownload(m.name)}
                          className={downloading === m.name ? 'cursor-not-allowed opacity-60' : ''}
                        >
                          {downloading === m.name ? 'Downloading...' : 'Download'}
                        </Button>
                      )}
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
