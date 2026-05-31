// frontend/src/components/interaction/InteractionModal.jsx
import { useInteractionStore } from '../../store/interactionStore'
import { ConfirmInteraction } from './ConfirmInteraction'
import { SelectInteraction } from './SelectInteraction'
import { TextInputInteraction } from './TextInputInteraction'
import { FormInteraction } from './FormInteraction'
import { Loader2 } from 'lucide-react'
import { useState, useEffect } from 'react'

export function InteractionModal() {
  const { queue, resolveInteraction, stopProxy } = useInteractionStore()
  const [loading, setLoading] = useState(false)

  // Cleanup expired interactions every second
  useEffect(() => {
    const interval = setInterval(() => {
      const { queue, removeInteraction } = useInteractionStore.getState()
      const now = new Date()

      queue.forEach((interaction) => {
        if (new Date(interaction.expires_at) < now) {
          removeInteraction(interaction.id)
        }
      })
    }, 1000) // Check every second

    return () => clearInterval(interval)
  }, [])

  // Find oldest interaction that needs attention
  const activeInteraction = queue.find(
    i => i.status === 'need_manual' || i.status === 'pending'
  )

  if (!activeInteraction) {
    return null
  }

  const { type, schema_data, status, id } = activeInteraction
  const isPending = status === 'pending'

  const handleAction = async (actionFn) => {
    setLoading(true)
    try {
      await actionFn()
    } catch (error) {
      console.error('Interaction action failed:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleResolve = (result) => {
    return handleAction(() => resolveInteraction(id, result))
  }

  const handleStopProxy = () => {
    return handleAction(() => stopProxy(id))
  }

  // Render appropriate interaction component based on type
  const renderInteraction = () => {
    const commonProps = {
      title: schema_data.title,
      prompt: schema_data.prompt,
      disabled: loading
    }

    switch (type) {
      case 'confirm':
        return (
          <ConfirmInteraction
            {...commonProps}
            onApprove={() => handleResolve({ decision: 'approved' })}
            onDeny={() => handleResolve({ decision: 'denied' })}
          />
        )

      case 'select':
        return (
          <SelectInteraction
            {...commonProps}
            options={schema_data.options || []}
            onSelect={(index) => handleResolve({ selected_index: index })}
            onCancel={() => handleResolve({ decision: 'denied' })}
          />
        )

      case 'text_input':
        return (
          <TextInputInteraction
            {...commonProps}
            onSubmit={(text) => handleResolve({ text })}
            onCancel={() => handleResolve({ decision: 'denied' })}
          />
        )

      case 'form':
        return (
          <FormInteraction
            {...commonProps}
            fields={schema_data.fields || []}
            onSubmit={(form) => handleResolve({ form })}
            onCancel={() => handleResolve({ decision: 'denied' })}
          />
        )

      default:
        return (
          <div className="text-red-400">
            Unknown interaction type: {type}
          </div>
        )
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-75">
      <div className="bg-gray-800 rounded-xl shadow-2xl w-full max-w-lg mx-4 max-h-[80vh] overflow-hidden flex flex-col">
        {/* Modal Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <div className="flex items-center gap-2">
            {loading && <Loader2 className="w-5 h-5 text-blue-400 animate-spin" />}
            <h2 className="text-lg font-semibold text-white">
              {isPending ? 'Proxy Running' : 'Action Required'}
            </h2>
          </div>
          {isPending && (
            <button
              onClick={handleStopProxy}
              disabled={loading}
              className="px-3 py-1 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Stop Proxy
            </button>
          )}
        </div>

        {/* Modal Content */}
        <div className="p-6 overflow-y-auto flex-1">
          {renderInteraction()}
        </div>
      </div>
    </div>
  )
}
