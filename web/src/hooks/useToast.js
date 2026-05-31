import { useToastStore } from '../store/toastStore'

export function useToast() {
  const { addToast, removeToast } = useToastStore()

  return {
    addToast: (toast) => {
      const entry = addToast(toast)
      setTimeout(() => {
        removeToast(entry.id)
      }, 5000)
    },
    removeToast,
  }
}
