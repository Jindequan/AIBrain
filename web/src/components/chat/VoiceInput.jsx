import { useState, useRef, useCallback, useEffect } from 'react'
import { Mic, Square, Loader, ChevronDown, AlertTriangle } from 'lucide-react'
import { Link } from 'react-router-dom'
import { buildApiUrl } from '../../api/client'
import { cn } from '../../lib/utils'

function RecordingOverlay({ interimText, audioLevel, onStop }) {
  useEffect(() => {
    const handler = (e) => { if (e.key === 'Escape') onStop() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onStop])

  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/70 backdrop-blur-sm select-none animate-[fadein_150ms_ease-out]">
      <style>{`@keyframes fadein{from{opacity:0}to{opacity:1}}`}</style>
      <button
        onClick={onStop}
        className="relative mb-8 focus:outline-none group"
        aria-label="Stop Recording"
      >
        <div className="absolute inset-0 rounded-full bg-red-400/20 animate-ping" style={{ width: 128, height: 128, left: -16, top: -16 }} />
        <div className="absolute inset-0 rounded-full bg-red-400/10 animate-ping" style={{ width: 128, height: 128, left: -16, top: -16, animationDelay: '0.3s' }} />
        <div className="flex items-center justify-center w-24 h-24 rounded-full bg-red-500 shadow-xl shadow-red-500/30 transition-transform group-active:scale-95">
          <Square className="w-8 h-8 text-white fill-current" />
        </div>
      </button>

      <p className="text-white/80 text-lg font-medium mb-4">Tap to stop recording</p>

      <div className="w-48 h-2 bg-white/10 rounded-full overflow-hidden mb-4">
        <div
          className="h-full rounded-full transition-all duration-75"
          style={{
            width: `${Math.min(audioLevel * 100, 100)}%`,
            backgroundColor: audioLevel > 0.02 ? '#22c55e' : '#ef444488'
          }}
        />
      </div>

      {interimText && (
        <div className="w-full max-w-lg px-6">
          <div className="bg-white/10 backdrop-blur rounded-2xl px-6 py-4 flex items-center justify-center">
            <p className="text-white text-center text-lg leading-relaxed">{interimText}</p>
          </div>
        </div>
      )}
    </div>
  )
}

function getActiveModel() {
  return localStorage.getItem('voice_active_model') || null
}

function getLanguagePreference() {
  return localStorage.getItem('voice_language') || 'auto'
}

export function VoiceInput({ onTranscript, disabled, compact = false }) {
  const [status, setStatus] = useState('idle')
  const [audioLevel, setAudioLevel] = useState(0)
  const [deviceList, setDeviceList] = useState([])
  const [selectedDeviceId, setSelectedDeviceId] = useState('')
  const [showDevicePicker, setShowDevicePicker] = useState(false)
  const micStreamRef = useRef(null)
  const mediaRecorderRef = useRef(null)
  const analyserRef = useRef(null)
  const audioRAFRef = useRef(null)
  const onTranscriptRef = useRef(onTranscript)
  const audioChunksRef = useRef([])

  useEffect(() => {
    onTranscriptRef.current = onTranscript
  }, [onTranscript])

  // Enumerate devices on mount
  useEffect(() => {
    navigator.mediaDevices.enumerateDevices().then((devices) => {
      const inputs = devices.filter(d => d.kind === 'audioinput')
      setDeviceList(inputs)
      const real = inputs.find(d => !d.label.includes('Virtual'))
      if (real) setSelectedDeviceId(real.deviceId)
      else if (inputs.length > 0) setSelectedDeviceId(inputs[0].deviceId)
    }).catch(() => {})
  }, [])

  const stopMic = useCallback(() => {
    if (audioRAFRef.current) {
      cancelAnimationFrame(audioRAFRef.current)
      audioRAFRef.current = null
    }
    analyserRef.current = null
    if (micStreamRef.current) {
      micStreamRef.current.getTracks().forEach(t => t.stop())
      micStreamRef.current = null
    }
    setAudioLevel(0)
  }, [])

  const stopListening = useCallback(() => {
    if (mediaRecorderRef.current && mediaRecorderRef.current.state === 'recording') {
      mediaRecorderRef.current.stop()
    }
    mediaRecorderRef.current = null

    stopMic()
    setStatus('transcribing')
  }, [stopMic])

  const sendToBackend = useCallback(async (blob) => {
    const model = getActiveModel()
    const language = getLanguagePreference()

    try {
      let body

      if (window.electronAPI?.saveTempFile) {
        // ── Electron mode: save to temp file, pass path ──
        const buffer = await blob.arrayBuffer()
        const filename = `voice_input_${Date.now()}.webm`
        const path = await window.electronAPI.saveTempFile(new Uint8Array(buffer), filename)
        body = { path, model: model || 'base' }
      } else {
        // ── Browser mode: base64 encode, pass inline ──
        const buffer = await blob.arrayBuffer()
        const bytes = new Uint8Array(buffer)
        let binary = ''
        for (let i = 0; i < bytes.length; i++) {
          binary += String.fromCharCode(bytes[i])
        }
        const base64 = btoa(binary)
        body = { audio: base64, model: model || 'base' }
      }

      if (language !== 'auto') {
        body.language = language
      }

      const res = await fetch(buildApiUrl('/api/v1/stt/transcribe'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })

      if (!res.ok) {
        const err = await res.text()
        console.error('[VoiceInput] backend error:', err)
        setStatus('idle')
        return
      }

      const data = await res.json()

      if (data.text && onTranscriptRef.current) {
        onTranscriptRef.current({ final: data.text, interim: '', isFinal: true })
      }

      setStatus('idle')
    } catch (e) {
      console.error('[VoiceInput] error:', e.message)
      setStatus('idle')
    }
  }, [])

  const startListening = useCallback(() => {
    setStatus('requesting')
    audioChunksRef.current = []

    const constraints = selectedDeviceId
      ? { audio: { deviceId: { exact: selectedDeviceId } } }
      : { audio: true }

    navigator.mediaDevices.getUserMedia(constraints)
      .then((stream) => {
        micStreamRef.current = stream

        const audioCtx = new AudioContext()
        const source = audioCtx.createMediaStreamSource(stream)
        const analyser = audioCtx.createAnalyser()
        analyser.fftSize = 256
        source.connect(analyser)
        analyserRef.current = analyser

        const dataArray = new Uint8Array(analyser.frequencyBinCount)
        const measure = () => {
          if (!analyserRef.current) return
          analyserRef.current.getByteTimeDomainData(dataArray)
          let sum = 0
          for (let i = 0; i < dataArray.length; i++) {
            const val = dataArray[i] / 128 - 1
            sum += val * val
          }
          setAudioLevel(Math.sqrt(sum / dataArray.length))
          audioRAFRef.current = requestAnimationFrame(measure)
        }
        measure()

        const recorder = new MediaRecorder(stream, { mimeType: 'audio/webm' })
        mediaRecorderRef.current = recorder
        audioChunksRef.current = []

        recorder.ondataavailable = (e) => {
          if (e.data.size > 0) audioChunksRef.current.push(e.data)
        }

        recorder.onstop = () => {
          if (audioChunksRef.current.length > 0) {
            const blob = new Blob(audioChunksRef.current, { type: 'audio/webm' })
            sendToBackend(blob)
          } else {
            setStatus('idle')
          }
        }

        recorder.start()
        setStatus('recording')
      })
      .catch((err) => {
        console.error('[VoiceInput] getUserMedia failed:', err.message)
        setStatus('idle')
      })
  }, [selectedDeviceId, sendToBackend])

  useEffect(() => {
    return () => { stopMic() }
  }, [stopMic])

  const toggle = useCallback(() => {
    if (status === 'recording') {
      stopListening()
    } else if (status === 'idle' || status === 'requesting') {
      startListening()
    }
  }, [status, stopListening, startListening])

  const selectDevice = useCallback((deviceId) => {
    setSelectedDeviceId(deviceId)
    setShowDevicePicker(false)
  }, [])

  const selectedDevice = deviceList.find(d => d.deviceId === selectedDeviceId)
  const activeModel = getActiveModel()

  // No active model → show disabled mic + link to Voice settings
  if (!activeModel) {
    if (compact) {
      return (
        <Link
          to="/voice"
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[#8a8d91] transition-colors hover:bg-black/[0.04] hover:text-[#62666a]"
          title="Voice model not activated, tap to configure"
          aria-label="Voice Settings"
        >
          <Mic className="h-5 w-5" />
        </Link>
      )
    }

    return (
      <Link
        to="/voice"
        className={cn(
          'p-2 rounded-xl transition-all shrink-0 flex items-center gap-1.5',
          'text-amber-500 hover:text-amber-600 hover:bg-amber-50'
        )}
        title="Voice model not activated, tap to configure"
        aria-label="Voice Settings"
      >
        <AlertTriangle className="w-4 h-4" />
        <span className="text-[11px] font-medium hidden sm:inline whitespace-nowrap">Voice Setup</span>
      </Link>
    )
  }

  return (
    <>
      <div className="flex items-end gap-1">
        <button
          onClick={toggle}
          disabled={disabled || status === 'transcribing'}
          className={cn(
            compact ? 'flex h-9 w-9 items-center justify-center rounded-full transition-all shrink-0' : 'p-2 rounded-xl transition-all shrink-0',
            status === 'recording' && 'bg-red-100 text-red-600 shadow-md',
            status === 'requesting' && 'bg-amber-100 text-amber-600',
            status === 'transcribing' && 'bg-blue-100 text-blue-600',
            status === 'idle' && (compact ? 'text-[#8a8d91] hover:bg-black/[0.04] hover:text-[#62666a]' : 'text-text-muted hover:text-text-primary hover:bg-gray-100')
          )}
          title={
            status === 'recording' ? 'Stop Recording' :
            status === 'transcribing' ? 'Transcribing...' : 'Voice Input'
          }
          aria-label="Voice Input"
        >
          {status === 'transcribing' ? (
            <Loader className={compact ? 'h-5 w-5 animate-spin' : 'w-4 h-4 animate-spin'} />
          ) : (
            <Mic className={compact ? 'h-5 w-5' : 'w-4 h-4'} />
          )}
        </button>

        {!compact && deviceList.length > 1 && status !== 'recording' && (
          <div className="relative">
            <button
              onClick={() => setShowDevicePicker(!showDevicePicker)}
              className="p-1 rounded-lg text-text-muted hover:text-text-primary hover:bg-gray-100 transition-all"
              title={selectedDevice?.label || 'Select Microphone'}
            >
              <ChevronDown className="w-3 h-3" />
            </button>
            {showDevicePicker && (
              <>
                <div className="fixed inset-0 z-40" onClick={() => setShowDevicePicker(false)} />
                <div className="absolute bottom-full left-0 mb-1 z-50 bg-white rounded-xl shadow-lg border border-card-border py-1 min-w-[200px]">
                  {deviceList.map((d) => (
                    <button
                      key={d.deviceId}
                      onClick={() => selectDevice(d.deviceId)}
                      className={cn(
                        'w-full text-left px-3 py-2 text-xs transition-colors',
                        d.deviceId === selectedDeviceId
                          ? 'bg-accent/10 text-accent font-medium'
                          : 'text-text-secondary hover:bg-gray-50'
                      )}
                    >
                      {d.label || `Mic ${d.deviceId.slice(0, 8)}`}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        )}
      </div>

      {status === 'recording' && (
        <RecordingOverlay
          interimText=""
          audioLevel={audioLevel}
          onStop={stopListening}
        />
      )}
    </>
  )
}
