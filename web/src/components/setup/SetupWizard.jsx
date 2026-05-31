import { useState } from 'react'
import { Sparkles, Key, Server, CheckCircle, ArrowRight, Loader2, AlertCircle } from 'lucide-react'
import { providersApi } from '../../api/providers.api'
import { useMutation, useQueryClient } from '@tanstack/react-query'

const PRESETS = [
  {
    id: 'deepseek',
    name: 'DeepSeek',
    description: 'Best value, recommended for beginners',
    fields: [
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'sk-...' },
      { key: 'base_url', label: 'Base URL', type: 'text', placeholder: 'https://api.deepseek.com', default: 'https://api.deepseek.com' },
    ],
    buildBody: (vals) => ({
      name: 'deepseek',
      protocol: 'openai',
      base_url: vals.base_url || 'https://api.deepseek.com',
      api_key: vals.api_key,
      models: {
        cheap: 'deepseek-chat',
        mid: 'deepseek-chat',
        strong: 'deepseek-chat',
        best: 'deepseek-chat',
      },
    }),
  },
  {
    id: 'openai',
    name: 'OpenAI',
    description: 'GPT-4o / GPT-4.1 series',
    fields: [
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'sk-...' },
      { key: 'base_url', label: 'Base URL', type: 'text', placeholder: 'https://api.openai.com/v1', default: 'https://api.openai.com/v1' },
    ],
    buildBody: (vals) => ({
      name: 'openai',
      protocol: 'openai',
      base_url: vals.base_url || 'https://api.openai.com/v1',
      api_key: vals.api_key,
      models: {
        cheap: 'gpt-4o-mini',
        mid: 'gpt-4o-mini',
        strong: 'gpt-4o',
        best: 'gpt-4o',
      },
    }),
  },
  {
    id: 'openrouter',
    name: 'OpenRouter',
    description: 'Aggregates many models, one API key',
    fields: [
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'sk-or-...' },
      { key: 'base_url', label: 'Base URL', type: 'text', placeholder: 'https://openrouter.ai/api/v1', default: 'https://openrouter.ai/api/v1' },
    ],
    buildBody: (vals) => ({
      name: 'openrouter',
      protocol: 'openai',
      base_url: vals.base_url || 'https://openrouter.ai/api/v1',
      api_key: vals.api_key,
      models: {
        cheap: 'deepseek/deepseek-chat-v3-0324',
        mid: 'anthropic/claude-3.5-haiku',
        strong: 'anthropic/claude-sonnet-4',
        best: 'anthropic/claude-sonnet-4',
      },
    }),
  },
  {
    id: 'custom',
    name: 'Custom (OpenAI compatible)',
    description: 'Any OpenAI-compatible API',
    fields: [
      { key: 'name', label: 'Name', type: 'text', placeholder: 'my-provider' },
      { key: 'base_url', label: 'Base URL', type: 'text', placeholder: 'https://your-api.com/v1' },
      { key: 'api_key', label: 'API Key', type: 'password', placeholder: 'sk-...' },
    ],
    buildBody: (vals) => ({
      name: vals.name || 'custom',
      protocol: 'openai',
      base_url: vals.base_url,
      api_key: vals.api_key,
      models: {
        cheap: vals.model || 'default',
        mid: vals.model || 'default',
        strong: vals.model || 'default',
        best: vals.model || 'default',
      },
    }),
  },
]

export function SetupWizard({ onComplete }) {
  const [step, setStep] = useState(0) // 0: welcome, 1: choose provider, 2: enter details, 3: done
  const [selectedPreset, setSelectedPreset] = useState(null)
  const [formValues, setFormValues] = useState({})
  const [error, setError] = useState(null)
  const queryClient = useQueryClient()

  const addProvider = useMutation({
    mutationFn: (body) => providersApi.add(body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['providers'] })
      setStep(3)
      if (onComplete) setTimeout(onComplete, 1500)
    },
    onError: (err) => {
      setError(err.message || 'Failed to add provider. Check your API key and URL.')
    },
  })

  function handlePresetSelect(preset) {
    setSelectedPreset(preset)
    // Pre-fill defaults
    const defaults = {}
    preset.fields.forEach((f) => {
      if (f.default) defaults[f.key] = f.default
    })
    setFormValues(defaults)
    setStep(2)
  }

  function handleSubmit() {
    setError(null)
    if (!selectedPreset) return
    // Validate required fields
    for (const f of selectedPreset.fields) {
      if (f.key !== 'base_url' && !formValues[f.key]?.trim()) {
        setError(`${f.label} is required`)
        return
      }
    }
    const body = selectedPreset.buildBody(formValues)
    addProvider.mutate(body)
  }

  // Step 0: Welcome
  if (step === 0) {
    return (
      <div className="max-w-lg mx-auto mt-20 p-8">
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-accent/10 rounded-2xl flex items-center justify-center mx-auto mb-4">
            <Sparkles className="w-8 h-8 text-accent" />
          </div>
          <h2 className="text-2xl font-bold text-text-primary mb-2">Welcome to AIBrain</h2>
          <p className="text-text-secondary">
            Your personal AI assistant. Let's set it up in 30 seconds.
          </p>
        </div>
        <button
          onClick={() => setStep(1)}
          className="w-full py-3 bg-accent text-white rounded-lg font-medium hover:bg-accent/90 transition-colors flex items-center justify-center gap-2"
        >
          Get Started <ArrowRight className="w-4 h-4" />
        </button>
      </div>
    )
  }

  // Step 1: Choose Provider
  if (step === 1) {
    return (
      <div className="max-w-lg mx-auto mt-12 p-8">
        <div className="mb-6">
          <h2 className="text-xl font-bold text-text-primary flex items-center gap-2">
            <Server className="w-5 h-5 text-accent" /> Choose AI Provider
          </h2>
          <p className="text-sm text-text-secondary mt-1">
            Select where your AI runs. You can add more later.
          </p>
        </div>
        <div className="space-y-3">
          {PRESETS.map((preset) => (
            <button
              key={preset.id}
              onClick={() => handlePresetSelect(preset)}
              className="w-full p-4 text-left rounded-lg border border-card-border hover:border-accent hover:bg-accent/5 transition-all group"
            >
              <p className="font-medium text-text-primary group-hover:text-accent">{preset.name}</p>
              <p className="text-sm text-text-muted mt-0.5">{preset.description}</p>
            </button>
          ))}
        </div>
        <button onClick={() => setStep(0)} className="mt-4 text-sm text-text-muted hover:text-text-primary">
          ← Back
        </button>
      </div>
    )
  }

  // Step 2: Enter Details
  if (step === 2 && selectedPreset) {
    return (
      <div className="max-w-lg mx-auto mt-12 p-8">
        <div className="mb-6">
          <h2 className="text-xl font-bold text-text-primary flex items-center gap-2">
            <Key className="w-5 h-5 text-accent" /> Configure {selectedPreset.name}
          </h2>
          <p className="text-sm text-text-secondary mt-1">
            Your API key is stored locally and never sent anywhere else.
          </p>
        </div>

        <div className="space-y-4">
          {selectedPreset.fields.map((field) => (
            <div key={field.key}>
              <label className="block text-sm font-medium text-text-secondary mb-1">{field.label}</label>
              <input
                type={field.type}
                value={formValues[field.key] || ''}
                onChange={(e) => setFormValues({ ...formValues, [field.key]: e.target.value })}
                placeholder={field.placeholder}
                className="w-full px-3 py-2 rounded-lg border border-input bg-input text-text-primary placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-accent/50"
              />
            </div>
          ))}
        </div>

        {error && (
          <div className="mt-4 p-3 rounded-lg bg-red-50 border border-red-200 flex items-center gap-2 text-red-700 text-sm">
            <AlertCircle className="w-4 h-4 shrink-0" />
            {error}
          </div>
        )}

        <button
          onClick={handleSubmit}
          disabled={addProvider.isPending}
          className="w-full mt-6 py-3 bg-accent text-white rounded-lg font-medium hover:bg-accent/90 transition-colors flex items-center justify-center gap-2 disabled:opacity-50"
        >
          {addProvider.isPending ? (
            <>
              <Loader2 className="w-4 h-4 animate-spin" /> Saving...
            </>
          ) : (
            <>
              Save & Start <ArrowRight className="w-4 h-4" />
            </>
          )}
        </button>

        <button onClick={() => setStep(1)} className="mt-4 text-sm text-text-muted hover:text-text-primary">
          ← Choose different provider
        </button>
      </div>
    )
  }

  // Step 3: Done
  return (
    <div className="max-w-lg mx-auto mt-20 p-8 text-center">
      <div className="w-16 h-16 bg-green-50 rounded-2xl flex items-center justify-center mx-auto mb-4">
        <CheckCircle className="w-8 h-8 text-green-500" />
      </div>
      <h2 className="text-2xl font-bold text-text-primary mb-2">You're all set!</h2>
      <p className="text-text-secondary mb-6">
        AIBrain is ready. Start chatting and give it tasks.
      </p>
      <button
        onClick={onComplete}
        className="px-8 py-3 bg-accent text-white rounded-lg font-medium hover:bg-accent/90 transition-colors"
      >
        Start Using AIBrain
      </button>
    </div>
  )
}
