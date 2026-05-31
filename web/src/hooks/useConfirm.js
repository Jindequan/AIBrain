import { useState, useCallback, useRef } from 'react'
import { AlertTriangle, X } from 'lucide-react'

export function useConfirm() {
  const [state, setState] = useState(null)
  const resolveRef = useRef(null)

  const confirm = useCallback((message, title) => {
    return new Promise((resolve) => {
      resolveRef.current = resolve
      setState({ message, title: title || 'Confirm' })
    })
  }, [])

  const handleConfirm = useCallback(() => {
    resolveRef.current?.(true)
    setState(null)
  }, [])

  const handleCancel = useCallback(() => {
    resolveRef.current?.(false)
    setState(null)
  }, [])

  const dialog = state ? (
    <div className="fixed inset-0 z-[200] flex items-center justify-center">
      <div className="fixed inset-0 bg-black/40" onClick={handleCancel} />
      <div className="relative bg-white rounded-2xl shadow-xl border border-card-border p-6 w-full max-w-sm mx-4">
        <div className="flex items-start gap-3">
          <div className="p-2 rounded-full bg-red-50 shrink-0">
            <AlertTriangle className="w-5 h-5 text-red-500" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="text-sm font-semibold text-text-primary">{state.title}</h3>
            <p className="text-sm text-text-secondary mt-1">{state.message}</p>
          </div>
          <button onClick={handleCancel} className="p-1 rounded-lg hover:bg-gray-100 text-text-muted shrink-0">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="flex justify-end gap-2 mt-4">
          <button onClick={handleCancel}
            className="px-4 py-2 text-sm font-medium text-text-secondary hover:bg-gray-100 rounded-xl transition-colors">
            Cancel
          </button>
          <button onClick={handleConfirm}
            className="px-4 py-2 text-sm font-medium text-white bg-red-500 hover:bg-red-600 rounded-xl transition-colors">
            Delete
          </button>
        </div>
      </div>
    </div>
  ) : null

  return { confirm, dialog }
}
