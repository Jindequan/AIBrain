// frontend/src/store/interactionStore.ts
import { create } from 'zustand'
import type { Interaction, InteractionResult } from '../models/types'
import { interactionsApi } from '../api/interactions.api'

interface InteractionStore {
  // Queue of interactions to display (pending + need_manual only)
  queue: Interaction[]

  // WebSocket connection state
  wsConnected: boolean

  // Actions
  addInteraction: (interaction: Interaction) => void
  updateInteraction: (id: string, updates: Partial<Interaction>) => void
  removeInteraction: (id: string) => void
  resolveInteraction: (id: string, result: InteractionResult) => Promise<void>
  stopProxy: (id: string) => Promise<void>
  setWsConnected: (connected: boolean) => void
  setQueue: (interactions: Interaction[]) => void
}

export const useInteractionStore = create<InteractionStore>((set, get) => ({
  queue: [],
  wsConnected: false,

  addInteraction: (interaction) => {
    const { queue } = get()

    // Only add if should be displayed (pending, proxy_running, or need_manual)
    if (interaction.status !== 'pending' && interaction.status !== 'proxy_running' && interaction.status !== 'need_manual') {
      return
    }

    // Check if already exists
    if (queue.some((i) => i.id === interaction.id)) {
      return
    }

    // Add to queue
    set({ queue: [...queue, interaction] })
  },

  updateInteraction: (id, updates) => {
    const { queue } = get()

    const updatedQueue = queue.map((interaction) =>
      interaction.id === id
        ? { ...interaction, ...updates }
        : interaction
    )

    // Remove if should no longer be displayed
    const filteredQueue = updatedQueue.filter(
      (interaction) =>
        interaction.status === 'pending' ||
        interaction.status === 'proxy_running' ||
        interaction.status === 'need_manual'
    )

    set({ queue: filteredQueue })
  },

  removeInteraction: (id) => {
    const { queue } = get()
    set({ queue: queue.filter((i) => i.id !== id) })
  },

  resolveInteraction: async (id, result) => {
    try {
      await interactionsApi.resolve(id, { result })
      // Remove from queue after successful resolution
      get().removeInteraction(id)
    } catch (error) {
      console.error('Failed to resolve interaction:', error)
      throw error
    }
  },

  stopProxy: async (id) => {
    try {
      await interactionsApi.stopProxy(id)
      // Update status to need_manual
      get().updateInteraction(id, { status: 'need_manual' })
    } catch (error) {
      console.error('Failed to stop proxy:', error)
      throw error
    }
  },

  setWsConnected: (connected) => {
    set({ wsConnected: connected })
  },

  setQueue: (interactions) => {
    // Filter to only show pending, proxy_running, and need_manual
    const filtered = interactions.filter(
      (i) => i.status === 'pending' || i.status === 'proxy_running' || i.status === 'need_manual'
    )
    set({ queue: filtered })
  },
}))
