// frontend/src/components/interaction/FormInteraction.jsx
import { FileEdit, X, Check } from 'lucide-react'
import { useState } from 'react'

export function FormInteraction({
  title,
  prompt,
  fields,
  onSubmit,
  onCancel,
  disabled = false
}) {
  const [formData, setFormData] = useState({})
  const [errors, setErrors] = useState({})

  const handleChange = (key, value) => {
    setFormData(prev => ({ ...prev, [key]: value }))
    // Clear error for this field when user starts typing
    if (errors[key]) {
      setErrors(prev => ({ ...prev, [key]: null }))
    }
  }

  const validate = () => {
    const newErrors = {}
    fields.forEach(field => {
      if (field.required && !formData[field.key]?.trim()) {
        newErrors[field.key] = `${field.label} is required`
      }
    })
    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const handleSubmit = () => {
    if (validate()) {
      onSubmit(formData)
    }
  }

  return (
    <div className="flex flex-col">
      {/* Header */}
      <div className="mb-4">
        <div className="flex items-center gap-2 mb-2">
          <FileEdit className="w-5 h-5 text-green-400" />
          <h3 className="text-lg font-semibold text-white">{title}</h3>
        </div>
        <p className="text-sm text-gray-300 whitespace-pre-wrap">{prompt}</p>
      </div>

      {/* Form Fields */}
      <div className="flex-1 overflow-y-auto mb-4">
        <div className="space-y-4">
          {fields.map((field) => (
            <div key={field.key}>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                {field.label}
                {field.required && <span className="text-red-400 ml-1">*</span>}
              </label>

              {field.type === 'text' && (
                <input
                  type="text"
                  value={formData[field.key] || ''}
                  onChange={(e) => handleChange(field.key, e.target.value)}
                  disabled={disabled}
                  className="w-full p-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none disabled:opacity-50 disabled:cursor-not-allowed"
                />
              )}

              {field.type === 'select' && (
                <select
                  value={formData[field.key] || ''}
                  onChange={(e) => handleChange(field.key, e.target.value)}
                  disabled={disabled}
                  className="w-full p-2 bg-gray-700 text-white rounded-lg border border-gray-600 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  <option value="">Select an option...</option>
                  {field.options?.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
              )}

              {errors[field.key] && (
                <p className="text-red-400 text-xs mt-1">{errors[field.key]}</p>
              )}
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
          onClick={handleSubmit}
          disabled={disabled}
          className="flex items-center gap-2 px-4 py-2 text-sm bg-green-600 hover:bg-green-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Check className="w-4 h-4" />
          Submit
        </button>
      </div>
    </div>
  )
}
