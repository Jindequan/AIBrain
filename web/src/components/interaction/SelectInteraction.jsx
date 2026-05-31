// frontend/src/components/interaction/SelectInteraction.jsx
import { List, X } from 'lucide-react'
import { useState } from 'react'

export function SelectInteraction({
  title,
  prompt,
  options,
  onSelect,
  onCancel,
  disabled = false
}) {
  const [selectedIndex, setSelectedIndex] = useState(null)

  const handleSelect = () => {
    if (selectedIndex !== null) {
      onSelect(selectedIndex)
    }
  }

  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="mb-4">
        <div className="flex items-center gap-2 mb-2">
          <List className="w-5 h-5 text-blue-400" />
          <h3 className="text-lg font-semibold text-white">{title}</h3>
        </div>
        <p className="text-sm text-gray-300 whitespace-pre-wrap">{prompt}</p>
      </div>

      {/* Options List */}
      <div className="flex-1 overflow-y-auto mb-4">
        <div className="space-y-2">
          {options.map((option, index) => (
            <div
              key={index}
              onClick={() => !disabled && setSelectedIndex(index)}
              className={`
                p-3 rounded-lg cursor-pointer transition-all
                ${selectedIndex === index
                  ? 'bg-blue-600 border-2 border-blue-400'
                  : 'bg-gray-700 hover:bg-gray-600 border-2 border-transparent'
                }
                ${disabled ? 'opacity-50 cursor-not-allowed' : ''}
              `}
            >
              <div className="text-sm text-white">{option}</div>
            </div>
          ))}
        </div>
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
          onClick={handleSelect}
          disabled={disabled || selectedIndex === null}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <List className="w-4 h-4" />
          Select
        </button>
      </div>
    </div>
  )
}
