// frontend/src/components/interaction/TextInputInteraction.jsx
import { FileText, X, Check } from 'lucide-react'
import { useState } from 'react'

export function TextInputInteraction({
  title,
  prompt,
  onSubmit,
  onCancel,
  disabled = false
}) {
  const [text, setText] = useState('')

  const handleSubmit = () => {
    if (text.trim()) {
      onSubmit(text.trim())
    }
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="mb-4">
        <div className="flex items-center gap-2 mb-2">
          <FileText className="w-5 h-5 text-purple-400" />
          <h3 className="text-lg font-semibold text-white">{title}</h3>
        </div>
        <p className="text-sm text-gray-300 whitespace-pre-wrap">{prompt}</p>
      </div>

      {/* Textarea Input */}
      <div className="flex-1 mb-4">
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={disabled}
          placeholder="Enter your response..."
          className="w-full h-40 p-3 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none resize-none disabled:opacity-50 disabled:cursor-not-allowed"
        />
      </div>

      {/* Buttons */}
      <div className="flex items-center justify-end gap-3 mt-6">
        <button
          onClick={onCancel}
          disabled={disabled}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-gray-600 hover:bg-gray-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <X className="w-4 h-4" />
          Cancel
        </button>
        <button
          onClick={handleSubmit}
          disabled={disabled || !text.trim()}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Check className="w-4 h-4" />
          Submit
        </button>
      </div>
    </div>
  )
}
