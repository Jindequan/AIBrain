import { create } from 'zustand'

const DEFAULT_DURATION = 6000

/**
 * Reusable onError handler for useMutation.
 * Usage: useMutation({ ..., onError: mutationError('Operation') })
 */
export function mutationError(title = 'Operation failed') {
  return (error) => {
    const msg = error instanceof Error ? error.message : String(error)
    useToastStore.getState().addToast({ title, message: msg, variant: 'error' })
  }
}

export const useToastStore = create((set) => ({
  toasts: [],

  addToast(toast) {
    const entry = {
      id: `toast-${Date.now()}-${Math.random()}`,
      title: toast.title || '',
      message: toast.message || '',
      variant: toast.variant || 'info',
      duration: toast.duration ?? DEFAULT_DURATION,
    }

    set((s) => ({
      toasts: [...s.toasts, entry],
    }))

    if (entry.duration > 0) {
      setTimeout(() => {
        set((s) => ({
          toasts: s.toasts.filter((t) => t.id !== entry.id),
        }))
      }, entry.duration)
    }

    return entry
  },

  removeToast(id) {
    set((s) => ({
      toasts: s.toasts.filter((t) => t.id !== id),
    }))
  },
}))
