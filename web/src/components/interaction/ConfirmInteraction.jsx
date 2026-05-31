// frontend/src/components/interaction/ConfirmInteraction.jsx
import { Check, X } from 'lucide-react'

export function ConfirmInteraction({ title, prompt, onApprove, onDeny, disabled = false }) {
  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="mb-4">
        <h3 className="text-lg font-semibold text-white mb-2">{title}</h3>
        <p className="text-sm text-gray-300 whitespace-pre-wrap">{prompt}</p>
      </div>

      {/* Buttons */}
      <div className="flex items-center justify-end gap-3 mt-6">
        <button
          onClick={onDeny}
          disabled={disabled}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <X className="w-4 h-4" />
          Deny
        </button>
        <button
          onClick={onApprove}
          disabled={disabled}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-green-600 hover:bg-green-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Check className="w-4 h-4" />
          Approve
        </button>
      </div>
    </div>
  )
}
