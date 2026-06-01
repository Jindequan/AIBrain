import { useRef, useEffect, useCallback, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowUp,
  Plus,
  Square,
  X,
  Target,
  Shield,
  Zap,
  MessageCircle,
  Search,
  Palette,
  Bot,
} from 'lucide-react'
import { cn } from '../../lib/utils'
import { VoiceInput } from './VoiceInput'
import { DirPicker } from './DirPicker'
import ModelSelector from './ModelSelector'
import { goalsApi } from '../../api/goals.api'
import { proxyApi } from '../../api/proxy.api'

const MODE_OPTIONS = [
  { value: 'chat', runMode: 'interactive', label: 'Chat', Icon: MessageCircle },
  { value: 'research', runMode: 'plan', label: 'Research', Icon: Search },
  { value: 'creation', runMode: 'interactive', label: 'Creation', Icon: Palette },
]

const AUTONOMY_OPTIONS = [
  { value: 0, label: 'Suggest', desc: 'Only suggest actions' },
  { value: 1, label: 'Assist', desc: 'Can read files & search' },
  { value: 2, label: 'Execute', desc: 'Can write, send, deploy' },
]

export function ChatInput({
  input, setInput, onSend, onStop, streaming,
  textareaExpanded,
  pendingImages, onRemoveImage, onAttachImage,
  workspacePath, onWorkspacePathChange, workspaceLocked,
  selectedGoalId, onSelectGoal,
  mode, onModeChange,
  autonomyLevel, onAutonomyLevelChange,
  availableModels, selectedModelSpec, onSelectModel,
}) {
  const textareaRef = useRef(null)
  const inputRowRef = useRef(null)
  const textareaHeightTimerRef = useRef(null)
  const [showGoals, setShowGoals] = useState(false)
  const [showMode, setShowMode] = useState(false)
  const [proxyActive, setProxyActive] = useState(false)
  const [proxyToggling, setProxyToggling] = useState(false)

  const { data: proxyStatus } = useQuery({
    queryKey: ['proxy-status'],
    queryFn: () => proxyApi.status(),
    staleTime: 10_000,
    refetchOnWindowFocus: true,
  })

  useEffect(() => {
    if (proxyStatus?.active !== undefined) setProxyActive(proxyStatus.active)
  }, [proxyStatus])

  const handleToggleProxy = useCallback(async () => {
    setProxyToggling(true)
    try {
      const res = await proxyApi.toggle(!proxyActive)
      setProxyActive(res.active)
    } catch (e) {
      console.error('Failed to toggle proxy:', e)
    } finally {
      setProxyToggling(false)
    }
  }, [proxyActive])
  const [showAutonomy, setShowAutonomy] = useState(false)

  const { data: goalsData } = useQuery({
    queryKey: ['goals-compact'],
    queryFn: () => goalsApi.list({ status: 'active' }),
    staleTime: 30000,
  })

  const goals = goalsData?.goals || []
  const selectedGoal = goals.find(g => g.id === selectedGoalId)

  const autoResizeTextarea = useCallback(() => {
    const el = textareaRef.current
    const container = inputRowRef.current
    if (!el || !container || !textareaExpanded) return

    if (textareaHeightTimerRef.current) {
      clearTimeout(textareaHeightTimerRef.current)
    }

    textareaHeightTimerRef.current = setTimeout(() => {
      requestAnimationFrame(() => {
        el.style.height = 'auto'
        const maxHeight = Math.max(
          container.ownerDocument?.documentElement?.clientHeight ?? 600,
          600,
        ) / 2
        el.style.height = Math.min(el.scrollHeight, maxHeight) + 'px'
      })
    }, 100)
  }, [textareaExpanded])

  useEffect(() => {
    const el = textareaRef.current
    if (!el) return
    if (!textareaExpanded) {
      el.style.height = ''
    } else {
      autoResizeTextarea()
    }
  }, [textareaExpanded, autoResizeTextarea])

  useEffect(() => {
    return () => {
      if (textareaHeightTimerRef.current) {
        clearTimeout(textareaHeightTimerRef.current)
      }
    }
  }, [])

  const handleKeyDown = useCallback((e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      if (streaming) {
        onStop?.()
      } else {
        onSend()
      }
    }
  }, [onSend, onStop, streaming])

  const handleChange = useCallback((e) => {
    setInput(e.target.value)
    autoResizeTextarea()
  }, [setInput, autoResizeTextarea])

  const closePopups = useCallback(() => {
    setShowGoals(false)
    setShowMode(false)
    setShowAutonomy(false)
  }, [])

  return (
    <div ref={inputRowRef} className="px-5 pt-3 pb-4">
      {/* Pending images */}
      {pendingImages && pendingImages.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-3 mx-auto w-full max-w-[900px]">
          {pendingImages.map((img, i) => (
            <div key={i} className="relative group">
              <img src={img.preview} alt="Upload preview"
                className="w-14 h-14 object-cover rounded-xl border border-gray-200 dark:border-gray-700" />
              <button onClick={() => onRemoveImage?.(i)}
                className="absolute -top-1.5 -right-1.5 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all hover:scale-110 shadow-md">
                <X className="w-2.5 h-2.5" />
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="chat-composer mx-auto w-full max-w-[900px] rounded-[24px] bg-[#f5f5f5] pb-3 shadow-[0_18px_42px_rgba(0,0,0,0.06)]">
        <div className="rounded-[24px] border border-[#dcdcdc] bg-white px-4 pb-3 pt-4 shadow-[0_1px_2px_rgba(0,0,0,0.05)] transition-shadow focus-within:shadow-[0_10px_28px_rgba(0,0,0,0.08)]">
          <textarea
            ref={textareaRef}
            value={input}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            disabled={streaming}
            rows={1}
            placeholder="Type a message..."
            className="block min-h-[56px] w-full resize-none bg-transparent text-[15px] leading-6 text-[#202124] placeholder:text-[#c4c7c9] focus:outline-none focus:ring-0 disabled:opacity-70 selection:bg-accent/20"
          />

          <div className="mt-4 flex items-center justify-between gap-3">
            <div className="flex min-w-0 items-center gap-2">
              <button onClick={onAttachImage} disabled={streaming}
                className="flex h-8 w-8 items-center justify-center rounded-full text-[#7a7d81] transition-colors hover:bg-black/[0.04] hover:text-[#4f5357] disabled:opacity-40"
                title="Attach image" aria-label="Attach image">
                <Plus className="h-4 w-4" />
              </button>
            </div>

            <div className="flex shrink-0 items-center gap-2">
              <VoiceInput onTranscript={({ final }) => { if (final) setInput(final) }} disabled={streaming} compact />
              <button onClick={streaming ? onStop : onSend}
                disabled={!streaming && !input.trim() && (!pendingImages || pendingImages.length === 0)}
                className={cn(
                  'flex h-9 w-9 items-center justify-center rounded-full transition-all shrink-0',
                  streaming
                    ? 'bg-red-500 text-white hover:bg-red-600'
                    : input.trim() || pendingImages?.length ? 'bg-accent text-white hover:bg-accent/90' : 'bg-gray-300 dark:bg-gray-700 text-white opacity-70'
                )}
                aria-label={streaming ? 'Stop generating' : 'Send message'}>
                {streaming ? <Square className="h-3.5 w-3.5 fill-current" /> : <ArrowUp className="h-4 w-4" />}
              </button>
            </div>
          </div>
        </div>

        <div className="flex min-w-0 items-center gap-2 px-4 pt-3 flex-wrap">
          <ModelSelector
            models={availableModels || []}
            selectedModelSpec={selectedModelSpec}
            onSelect={onSelectModel}
          />
          <DirPicker
            value={workspacePath}
            onChange={onWorkspacePathChange}
            disabled={workspaceLocked}
            variant="compact"
          />
          {workspaceLocked && (
            <span className="text-[10px] text-text-muted/60">· Session active</span>
          )}

          {/* Goal selector */}
          <div className="relative">
            <button
              onClick={() => { closePopups(); setShowGoals(!showGoals) }}
              disabled={workspaceLocked}
              className={cn(
                'flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium transition-colors border',
                selectedGoalId
                  ? 'bg-accent/10 text-accent border-accent/30'
                  : 'bg-gray-100 dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30'
              )}
            >
              <Target className="w-3 h-3" />
              <span className="max-w-[80px] truncate">{selectedGoal ? selectedGoal.title : 'Goal'}</span>
              {selectedGoalId && <X className="w-2.5 h-2.5 ml-0.5" onClick={(e) => { e.stopPropagation(); onSelectGoal?.(null) }} />}
            </button>
            {showGoals && (
              <div className="absolute bottom-full mb-1 left-0 z-50 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-lg min-w-[200px] max-h-[200px] overflow-y-auto">
                {goals.length === 0 ? (
                  <div className="px-3 py-2 text-[10px] text-text-muted">No active goals</div>
                ) : goals.map(g => (
                  <button key={g.id}
                    onClick={() => { onSelectGoal?.(g.id); setShowGoals(false) }}
                    className={cn(
                      'w-full text-left px-3 py-1.5 text-xs hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors',
                      g.id === selectedGoalId && 'text-accent font-medium'
                    )}>
                    {g.title}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Mode selector */}
          <div className="relative">
            <button
              onClick={() => { closePopups(); setShowMode(!showMode) }}
              className={cn(
                'flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium transition-colors border',
                mode && mode !== 'chat'
                  ? 'bg-blue-500/10 text-blue-600 border-blue-500/30'
                  : 'bg-gray-100 dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30'
              )}
            >
              <Zap className="w-3 h-3" />
              <span>{MODE_OPTIONS.find(m => m.value === (mode || 'chat'))?.label || 'Chat'}</span>
            </button>
            {showMode && (
              <div className="absolute bottom-full mb-1 left-0 z-50 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-lg min-w-[140px]">
                {MODE_OPTIONS.map(m => (
                  <ModeOption
                    key={m.value}
                    option={m}
                    selected={m.value === mode}
                    onSelect={() => { onModeChange?.(m.value, m.runMode); setShowMode(false) }}
                  />
                ))}
              </div>
            )}
          </div>

          {/* Autonomy level */}
          <div className="relative">
            <button
              onClick={() => { closePopups(); setShowAutonomy(!showAutonomy) }}
              className={cn(
                'flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium transition-colors border',
                autonomyLevel > 0
                  ? 'bg-amber-500/10 text-amber-600 border-amber-500/30'
                  : 'bg-gray-100 dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30'
              )}
            >
              <Shield className="w-3 h-3" />
              <span>{AUTONOMY_OPTIONS.find(a => a.value === (autonomyLevel || 0))?.label || 'Suggest'}</span>
            </button>
            {showAutonomy && (
              <div className="absolute bottom-full mb-1 left-0 z-50 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-lg min-w-[180px]">
                {AUTONOMY_OPTIONS.map(a => (
                  <button key={a.value}
                    onClick={() => { onAutonomyLevelChange?.(a.value); setShowAutonomy(false) }}
                    className={cn(
                      'w-full text-left px-3 py-1.5 text-xs hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors',
                      a.value === autonomyLevel && 'text-accent font-medium'
                    )}>
                    <div className="font-medium">{a.label}</div>
                    <div className="text-text-muted text-[10px]">{a.desc}</div>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Proxy toggle */}
          <button
            onClick={handleToggleProxy}
            disabled={proxyToggling}
            className={cn(
              'flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium transition-colors border',
              proxyActive
                ? 'bg-green-500/10 text-green-600 border-green-500/30'
                : 'bg-gray-100 dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30'
            )}
            title={proxyActive ? 'Proxy is auto-approving tools' : 'Proxy off — manual approval required'}
          >
            <Bot className={cn('w-3 h-3', proxyToggling && 'animate-pulse')} />
            <span>{proxyActive ? 'Proxy ON' : 'Proxy OFF'}</span>
          </button>
        </div>
      </div>
    </div>
  )
}

function ModeOption({ option, selected, onSelect }) {
  const Icon = option.Icon
  return (
    <button
      onClick={onSelect}
      className={cn(
        'w-full text-left px-3 py-1.5 text-xs hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors flex items-center gap-2',
        selected && 'text-accent font-medium'
      )}
    >
      <Icon className="w-3 h-3" />
      {option.label}
    </button>
  )
}
