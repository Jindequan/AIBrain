import { create } from 'zustand'

const WORKSPACE_KEY = 'aibrain_workspace_path'

let _progressiveGen = 0

export const useChatStore = create((set) => ({
  _finished: false,
  sessions: [],
  activeSessionId: null,
  activeWorkspacePath: null,
  messages: [],
  streaming: false,
  userStreaming: false,
  status: null,

  setSessions: (sessions) => set({ sessions }),

  /**
   * Set messages in unified format
   * Supports functional updates for message deletion
   */
  setMessages: (messages) => {
    if (typeof messages === 'function') {
      set((s) => ({ messages: messages(s.messages) }))
    } else {
      set({
        messages: mergeToolMessages(messages.map(m => ({
          ...m,
          content: normalizeContent(m.content),
          streaming: false
        })))
      })
    }
  },

  /**
   * Progressive message loading for large sessions
   * Merge consecutive assistant messages for consistent history and SSE display
   */
  setMessagesProgressive(messages) {
    const BATCH_SIZE = 20
    const gen = ++_progressiveGen
    const normalized = mergeToolMessages(messages.map(m => ({
      ...m,
      content: normalizeContent(m.content),
      streaming: false
    })))

    if (normalized.length <= BATCH_SIZE) {
      set({ messages: normalized })
      return
    }

    // Load first batch immediately (most recent messages)
    const firstBatch = normalized.slice(-BATCH_SIZE)
    set({ messages: firstBatch, _loadingOlder: true })

    // Load remaining messages in batches without blocking
    const remaining = normalized.slice(0, -BATCH_SIZE)

    function loadNextBatch() {
      // Cancelled — session changed while loading
      if (gen !== _progressiveGen) return
      if (remaining.length === 0) {
        set({ _loadingOlder: false })
        return
      }

      const batch = remaining.splice(-BATCH_SIZE)

      set((s) => ({
        messages: [...batch, ...s.messages],
        _loadingOlder: remaining.length > 0,
      }))

      if (remaining.length > 0) {
        if (typeof requestIdleCallback !== 'undefined') {
          requestIdleCallback(() => setTimeout(loadNextBatch, 0))
        } else {
          setTimeout(loadNextBatch, 0)
        }
      }
    }

    setTimeout(loadNextBatch, 100)
  },

  setActiveSession: (id) => set({
    activeSessionId: id,
    messages: [],
    streaming: false,
    userStreaming: false,
    _finished: false,
    status: null,
  }),

  setActiveWorkspacePath: (path) => {
    try {
      if (path) localStorage.setItem(WORKSPACE_KEY, path)
      else localStorage.removeItem(WORKSPACE_KEY)
    } catch { /* localStorage unavailable */ }
    set({ activeWorkspacePath: path })
  },

  setScrollTarget: (sessionId, messageIndex) => set({
    scrollTargetSessionId: sessionId,
    scrollTargetMessageIndex: messageIndex,
  }),

  clearScrollTarget: () => set({
    scrollTargetSessionId: null,
    scrollTargetMessageIndex: null,
  }),

  setStatus(status) {
    set({ status })
  },

  startStreaming() {
    set((s) => ({
      _finished: false,
      streaming: true,
      userStreaming: true,
      status: null,
      messages: [...s.messages, { role: 'assistant', content: [], streaming: true, created_at: new Date().toISOString() }],
    }))
  },

  appendTextDelta(delta) {
    if (!delta || !delta.trim()) return

    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || !Array.isArray(last.content)) return s

      const content = [...(last.content || [])]
      const lastBlock = content[content.length - 1]
      if (lastBlock?.type === 'text') {
        content[content.length - 1] = { ...lastBlock, text: lastBlock.text + delta }
      } else {
        content.push({ type: 'text', text: delta })
      }
      msgs[msgs.length - 1] = { ...last, content }
      return { messages: msgs }
    })
  },

  appendAssistantTextIfEmpty(text) {
    if (!text || text === '') return

    set((s) => {
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || last.role !== 'assistant' || !Array.isArray(last.content)) return s

      const hasText = last.content.some((block) => block.type === 'text' && block.text)
      if (hasText) return s

      msgs[msgs.length - 1] = {
        ...last,
        content: [...last.content, { type: 'text', text }],
      }
      return { messages: msgs }
    })
  },

  startThinkingBlock(index) {
    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || last.role !== 'assistant') return s

      const content = [...(last.content || [])]
      // Only add thinking block if it does not exist
      if (!content.some((b) => b.type === 'thinking' && b.thinking_index === index)) {
        content.push({ type: 'thinking', thinking_index: index, text: '' })
        msgs[msgs.length - 1] = { ...last, content }
        return { messages: msgs }
      }
      // Skip update if already exists
      return s
    })
  },

  appendThinkingDelta(index, text) {
    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || !Array.isArray(last.content)) return s

      // Check if thinking block needs updating
      const hasThinkingBlock = last.content.some(b => b.type === 'thinking' && b.thinking_index === index)
      if (!hasThinkingBlock) return s

      const content = last.content.map((b) =>
        b.type === 'thinking' && b.thinking_index === index
          ? { ...b, text: b.text + text }
          : b
      )

      msgs[msgs.length - 1] = { ...last, content }
      return { messages: msgs }
    })
  },

  endThinkingBlock(index) {
    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || !Array.isArray(last.content)) return s

      const content = last.content.map((b) =>
        b.type === 'thinking' && b.thinking_index === index
          ? { ...b, finished: true }
          : b
      )

      msgs[msgs.length - 1] = { ...last, content }
      return { messages: msgs }
    })
  },

  addToolUse(name, id, input) {
    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || !Array.isArray(last.content)) return s

      const content = [...(last.content || [])]
      // Skip if tool_use with same ID already exists
      if (content.some(b => b.type === 'tool_use' && b.id === id)) return s

      content.push({ type: 'tool_use', id, name, input: input || {}, output: null, status: 'running' })
      msgs[msgs.length - 1] = { ...last, content }
      return { messages: msgs }
    })
  },

  appendToolInputDelta(toolUseIndex, chunk) {
    if (!chunk) return
    set((s) => {
      if (!s.streaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (!last || !last.streaming || !Array.isArray(last.content)) return s
      // Find the last running tool_use block and append to its input display
      const content = [...last.content]
      for (let i = content.length - 1; i >= 0; i--) {
        if (content[i].type === 'tool_use' && content[i].status === 'running') {
          const existingInput = typeof content[i].input === 'string'
            ? content[i].input
            : JSON.stringify(content[i].input || {})
          content[i] = { ...content[i], input: existingInput + chunk }
          break
        }
      }
      msgs[msgs.length - 1] = { ...last, content }
      return { messages: msgs }
    })
  },

  setToolResult(toolUseId, output, status = 'success') {
    set((s) => {
      const msgs = [...s.messages]
      // Find the message containing this tool_use (any of the last messages)
      for (let i = msgs.length - 1; i >= 0; i--) {
        const msg = msgs[i]
        if (msg.role === 'assistant' && Array.isArray(msg.content)) {
          const hasToolUse = msg.content.some(b => b.type === 'tool_use' && b.id === toolUseId)
          if (hasToolUse) {
            msgs[i] = {
              ...msg,
              content: msg.content.map(b =>
                b.type === 'tool_use' && b.id === toolUseId
                  ? { ...b, output, status }
                  : b
              )
            }
            break
          }
        }
      }
      return { messages: msgs }
    })
  },

  finishStreaming(errorMsg) {
    set((s) => {
      if (s._finished && !errorMsg) return s
      if (s._finished && errorMsg && s.messages.length > 0) {
        const last = s.messages[s.messages.length - 1]
        if (last?.role === 'system' && last?.error) return s
      }

      const msgs = [...s.messages]
      if (msgs.length > 0) {
        msgs[msgs.length - 1] = { ...msgs[msgs.length - 1], streaming: false }
      }
      const updated = errorMsg
        ? [...msgs, { role: 'system', content: [{ type: 'text', text: `Error: ${errorMsg}` }], error: true }]
        : msgs
      return { messages: updated, streaming: false, userStreaming: false, status: null, _finished: true }
    })
  },

  /**
   * Called when streaming is interrupted (e.g. connection loss).
   * Preserves partial content, marks message as incomplete.
   */
  interruptStreaming() {
    set((s) => {
      if (s._finished) return s
      const msgs = [...s.messages]
      if (msgs.length > 0) {
        const last = msgs[msgs.length - 1]
        const isEmptyAssistant =
          last?.role === 'assistant' &&
          Array.isArray(last.content) &&
          last.content.length === 0

        if (isEmptyAssistant) {
          msgs.pop()
        } else {
          msgs[msgs.length - 1] = { ...last, streaming: false, incomplete: true }
        }
      }
      return { messages: msgs, streaming: false, userStreaming: false, status: null, _finished: true }
    })
  },

  addSystemMessage(text, type) {
    set((s) => ({
      messages: [...s.messages, { role: 'system', content: [{ type: 'text', text }], system: true, system_type: type }],
    }))
  },

  addApprovalRequiredMessage(approval = {}) {
    set((s) => {
      const approvalId = approval.approval_id || approval.interaction_id
      const alreadyShown = approvalId && s.messages.some((msg) =>
        msg.system_type === 'approval_required' &&
        (msg.approval?.approval_id === approvalId || msg.approval?.interaction_id === approvalId)
      )
      const streamingPatch = {
        streaming: true,
        userStreaming: true,
        _finished: false,
        status: { text: 'Waiting for approval', type: 'warning' },
      }

      if (alreadyShown) {
        return streamingPatch
      }

      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      const isEmptyAssistant =
        last?.role === 'assistant' &&
        Array.isArray(last.content) &&
        last.content.length === 0

      if (isEmptyAssistant) {
        msgs[msgs.length - 1] = { ...last, streaming: true }
      } else if (last?.role === 'assistant' && last?.streaming) {
        msgs[msgs.length - 1] = { ...last, streaming: true }
      }

      const reason = approval.reason || approval.title || 'This request needs your approval before it can continue.'
      const tool = approval.tool_name ? `\nTool: ${approval.tool_name}` : ''
      const run = approval.run_id ? `\nRun: ${approval.run_id}` : ''
      const text = `Waiting for approval\n${reason}${tool}${run}`

      return {
        ...streamingPatch,
        messages: [
          ...msgs,
          {
            role: 'system',
            content: [{ type: 'text', text }],
            system: true,
            system_type: 'approval_required',
            approval: {
              ...approval,
              approval_id: approvalId,
              interaction_id: approval.interaction_id || approvalId,
            },
            created_at: new Date().toISOString(),
          },
        ],
      }
    })
  },

  resumeStreamingAfterApproval() {
    set((s) => {
      if (!s.userStreaming) return s
      const msgs = [...s.messages]
      const last = msgs[msgs.length - 1]
      if (last?.role === 'assistant') {
        msgs[msgs.length - 1] = { ...last, streaming: true }
      } else {
        msgs.push({ role: 'assistant', content: [], streaming: true, created_at: new Date().toISOString() })
      }
      return {
        messages: msgs,
        streaming: true,
        _finished: false,
        status: { text: 'Resuming...', type: 'info' },
      }
    })
  },

  prependMessages(older) {
    set((s) => ({ messages: [...older, ...s.messages] }))
  },

  addUserMessage(content) {
    const blocks = typeof content === 'string'
      ? [{ type: 'text', text: content }]
      : content;
    set((s) => ({
      messages: [...s.messages, { role: 'user', content: blocks, created_at: new Date().toISOString() }],
    }))
  },
}))

/**
 * Merge tool messages into assistant messages for unified blocks
 * Handles two cases:
 * 1. Legacy: assistant(tool_use) + tool(tool_result) -> merge
 * 2. Split: multiple assistant messages -> merge
 */
function mergeToolMessages(messages) {
  // Collect all tool_result from tool messages
  const toolResults = new Map()
  const filtered = messages.filter(m => {
    if (m.role === 'tool' && Array.isArray(m.content)) {
      for (const block of m.content) {
        if (block.type === 'tool_result') {
          toolResults.set(block.tool_use_id, block.content)
        }
      }
      return false // Remove tool messages
    }
    return true
  })

  // Merge tool_results into assistant tool_use blocks
  const withResults = filtered.map(m => {
    if (m.role === 'assistant' && Array.isArray(m.content)) {
      const hasToolUse = m.content.some(b => b.type === 'tool_use')
      if (hasToolUse) {
        const content = m.content.map(block => {
          if (block.type === 'tool_use' && toolResults.has(block.id)) {
            return { ...block, output: toolResults.get(block.id), status: 'success' }
          }
          return block
        })
        return { ...m, content }
      }
    }
    return m
  })

  // Merge consecutive assistant messages (multi-turn agent split)
  const merged = []
  let i = 0
  while (i < withResults.length) {
    const current = withResults[i]
    if (current.role === 'assistant') {
      // Collect all consecutive assistant messages
      let j = i + 1
      while (j < withResults.length && withResults[j].role === 'assistant') {
        j++
      }
      if (j > i + 1) {
        // Merge all consecutive assistants into one
        const mergedContent = withResults.slice(i, j).flatMap(m => m.content || [])
        merged.push({ ...current, content: mergedContent })
        i = j
      } else {
        merged.push(current)
        i++
      }
    } else {
      merged.push(current)
      i++
    }
  }

  return merged
}

/**
 * Normalize content to array format
 */
function normalizeContent(content) {
  if (Array.isArray(content)) return content
  if (typeof content === 'string' && content) return [{ type: 'text', text: content }]
  return []
}
