import { useEffect, useRef } from 'react'
import { X } from 'lucide-react'
import { cn } from '../../lib/utils.js'

export function Modal({ open, onClose, title, children, size = 'md' }) {
  const overlayRef = useRef(null)
  const modalRef = useRef(null)

  useEffect(() => {
    if (!open) return

    const handleEscape = (e) => {
      if (e.key === 'Escape') onClose()
    }

    const handleOverlayClick = (e) => {
      if (e.target === overlayRef.current) onClose()
    }

    const overlay = overlayRef.current
    document.addEventListener('keydown', handleEscape)
    overlay?.addEventListener('click', handleOverlayClick)

    // Focus first input
    setTimeout(() => {
      const firstInput = modalRef.current?.querySelector('input, textarea, select')
      firstInput?.focus()
    }, 100)

    return () => {
      document.removeEventListener('keydown', handleEscape)
      overlay?.removeEventListener('click', handleOverlayClick)
    }
  }, [open, onClose])

  if (!open) return null

  const sizeClasses = {
    sm: 'max-w-md',
    md: 'max-w-lg',
    lg: 'max-w-2xl',
    xl: 'max-w-3xl',
  }

  return (
    <div
      ref={overlayRef}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
    >
      <div
        ref={modalRef}
        className={cn(
          'w-full bg-card-bg rounded-2xl shadow-2xl border border-card-border max-h-[90vh] overflow-hidden flex flex-col',
          sizeClasses[size]
        )}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-card-border">
          <h2 className="text-lg font-semibold text-text-primary">{title}</h2>
          <button
            onClick={onClose}
            aria-label="Close modal"
            className="p-1 rounded-lg hover:bg-gray-100 text-text-muted hover:text-text-primary transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-auto px-5 py-4">
          {children}
        </div>
      </div>
    </div>
  )
}
