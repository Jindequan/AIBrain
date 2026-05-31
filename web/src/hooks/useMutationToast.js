import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useToastStore } from '../store/toastStore'

/**
 * useMutation with automatic error toast.
 * Usage: same as useMutation but onError shows a toast automatically.
 */
export function useMutationToast({ successTitle, invalidateQueries, ...opts }) {
  const queryClient = useQueryClient()
  const addToast = useToastStore((s) => s.addToast)

  return useMutation({
    ...opts,
    onError: (error, variables, context) => {
      const msg = error instanceof Error ? error.message : String(error)
      addToast({ title: 'Operation failed', message: msg, variant: 'error' })
      opts.onError?.(error, variables, context)
    },
    onSuccess: (data, variables, context) => {
      if (successTitle) {
        addToast({ title: successTitle, variant: 'success' })
      }
      if (invalidateQueries) {
        const keys = Array.isArray(invalidateQueries[0]) ? invalidateQueries : [invalidateQueries]
        keys.forEach((key) => queryClient.invalidateQueries({ queryKey: key }))
      }
      opts.onSuccess?.(data, variables, context)
    },
  })
}
