import { useChatStore } from '../chatStore'

beforeEach(() => {
  useChatStore.setState({
    _finished: false,
    sessions: [],
    activeSessionId: null,
    messages: [],
    streaming: false,
    status: null,
  })
})

describe('chatStore', () => {
  describe('appendTextDelta', () => {
    it('appends text to an existing text block', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          {
            role: 'assistant',
            content: [{ type: 'text', text: 'Hello' }],
            streaming: true,
          },
        ],
      })

      useChatStore.getState().appendTextDelta(' world')

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content[0].text).toBe('Hello world')
    })

    it('creates a new text block when last block is not text', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          {
            role: 'assistant',
            content: [{ type: 'tool_use', id: 't1', name: 'bash', input: {} }],
            streaming: true,
          },
        ],
      })

      useChatStore.getState().appendTextDelta('Hello')

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content).toHaveLength(2)
      expect(msgs[0].content[1]).toEqual({
        type: 'text',
        text: 'Hello',
      })
    })

    it('skips empty deltas to avoid re-renders', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          {
            role: 'assistant',
            content: [{ type: 'text', text: 'Hello' }],
            streaming: true,
          },
        ],
      })

      useChatStore.getState().appendTextDelta('')
      useChatStore.getState().appendTextDelta(null)

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content[0].text).toBe('Hello')
    })

    it('does nothing when there are no messages', () => {
      useChatStore.setState({ messages: [] })

      useChatStore.getState().appendTextDelta(' world')

      const msgs = useChatStore.getState().messages
      expect(msgs).toHaveLength(0)
    })
  })

  describe('appendAssistantTextIfEmpty', () => {
    it('fills the last assistant message when no text delta was streamed', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          { role: 'assistant', content: [], streaming: true },
        ],
      })

      useChatStore.getState().appendAssistantTextIfEmpty('final answer')

      expect(useChatStore.getState().messages[0].content).toEqual([
        { type: 'text', text: 'final answer' },
      ])
    })

    it('does not duplicate text when deltas already populated the message', () => {
      useChatStore.setState({
        messages: [
          { role: 'assistant', content: [{ type: 'text', text: 'streamed' }], streaming: true },
        ],
      })

      useChatStore.getState().appendAssistantTextIfEmpty('final answer')

      expect(useChatStore.getState().messages[0].content).toEqual([
        { type: 'text', text: 'streamed' },
      ])
    })
  })

  describe('addToolUse', () => {
    it('adds a tool_use block to the last assistant message', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          { role: 'assistant', content: [], streaming: true },
        ],
      })

      useChatStore.getState().addToolUse('bash', 't1', { cmd: 'ls' })

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content[0]).toMatchObject({
        type: 'tool_use',
        id: 't1',
        name: 'bash',
        input: { cmd: 'ls' },
        output: null,
        status: 'running',
      })
    })

    it('does not add a duplicate tool_use with the same id', () => {
      useChatStore.setState({
        streaming: true,
        messages: [
          {
            role: 'assistant',
            content: [{ type: 'tool_use', id: 't1', name: 'bash', input: {} }],
            streaming: true,
          },
        ],
      })

      useChatStore.getState().addToolUse('bash', 't1', {})

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content).toHaveLength(1)
    })
  })

  describe('setToolResult', () => {
    it('updates the tool_use block output and status', () => {
      useChatStore.setState({
        messages: [
          {
            role: 'assistant',
            content: [
              { type: 'tool_use', id: 't1', name: 'bash', input: {}, output: null, status: 'running' },
            ],
            streaming: true,
          },
        ],
      })

      useChatStore.getState().setToolResult('t1', 'file list', 'success')

      const msgs = useChatStore.getState().messages
      expect(msgs[0].content[0].output).toBe('file list')
      expect(msgs[0].content[0].status).toBe('success')
    })

    it('finds the tool_use in earlier messages if not in the last', () => {
      useChatStore.setState({
        messages: [
          { role: 'user', content: [{ type: 'text', text: 'run ls' }] },
          {
            role: 'assistant',
            content: [
              { type: 'tool_use', id: 't1', name: 'bash', input: {}, output: null, status: 'running' },
            ],
            streaming: true,
          },
          { role: 'user', content: [{ type: 'text', text: 'continue' }] },
        ],
      })

      useChatStore.getState().setToolResult('t1', 'files: foo bar', 'success')

      const msgs = useChatStore.getState().messages
      expect(msgs[1].content[0].output).toBe('files: foo bar')
    })
  })

  describe('finishStreaming', () => {
    it('sets streaming to false and marks as finished', () => {
      useChatStore.setState({
        messages: [
          { role: 'assistant', content: [{ type: 'text', text: 'done' }], streaming: true },
        ],
        streaming: true,
      })

      useChatStore.getState().finishStreaming()

      const state = useChatStore.getState()
      expect(state.streaming).toBe(false)
      expect(state._finished).toBe(true)
      expect(state.messages[0].streaming).toBe(false)
    })

    it('appends an error system message when errorMsg is provided', () => {
      useChatStore.setState({
        messages: [
          { role: 'assistant', content: [{ type: 'text', text: 'partial' }], streaming: true },
        ],
        streaming: true,
      })

      useChatStore.getState().finishStreaming('Connection lost')

      const msgs = useChatStore.getState().messages
      expect(msgs).toHaveLength(2)
      expect(msgs[1].role).toBe('system')
      expect(msgs[1].error).toBe(true)
      expect(msgs[1].content[0].text).toContain('Connection lost')
    })

    it('is idempotent when called without error', () => {
      useChatStore.setState({
        messages: [
          { role: 'assistant', content: [{ type: 'text', text: 'done' }], streaming: false },
        ],
        streaming: false,
        _finished: true,
      })

      // Should not mutate state
      const before = useChatStore.getState().messages.length
      useChatStore.getState().finishStreaming()
      expect(useChatStore.getState().messages.length).toBe(before)
    })
  })

  describe('interruptStreaming', () => {
    it('removes an empty assistant placeholder when generation is interrupted before any content', () => {
      useChatStore.setState({
        messages: [
          { role: 'user', content: [{ type: 'text', text: 'hello' }] },
          { role: 'assistant', content: [], streaming: true },
        ],
        streaming: true,
      })

      useChatStore.getState().interruptStreaming()

      const state = useChatStore.getState()
      expect(state.streaming).toBe(false)
      expect(state.messages).toHaveLength(1)
      expect(state.messages[0].role).toBe('user')
    })

    it('marks partial assistant content incomplete when interrupted', () => {
      useChatStore.setState({
        messages: [
          { role: 'assistant', content: [{ type: 'text', text: 'partial' }], streaming: true },
        ],
        streaming: true,
      })

      useChatStore.getState().interruptStreaming()

      const state = useChatStore.getState()
      expect(state.messages[0].streaming).toBe(false)
      expect(state.messages[0].incomplete).toBe(true)
    })
  })

  describe('addApprovalRequiredMessage', () => {
    it('replaces an empty streaming placeholder with an actionable approval message', () => {
      useChatStore.setState({
        messages: [
          { role: 'user', content: [{ type: 'text', text: 'review project' }] },
          { role: 'assistant', content: [], streaming: true },
        ],
        streaming: true,
      })

      useChatStore.getState().addApprovalRequiredMessage({
        approval_id: 'int-1',
        interaction_id: 'int-1',
        run_id: 'run-1',
        reason: 'Workspace access needs approval',
      })

      const state = useChatStore.getState()
      expect(state.streaming).toBe(false)
      expect(state.status).toEqual({ text: 'Waiting for approval', type: 'warning' })
      expect(state.messages).toHaveLength(2)
      expect(state.messages[1].role).toBe('system')
      expect(state.messages[1].system_type).toBe('approval_required')
      expect(state.messages[1].approval.approval_id).toBe('int-1')
      expect(state.messages[1].content[0].text).toContain('Workspace access needs approval')
    })

    it('does not duplicate the same approval prompt', () => {
      const approval = { approval_id: 'int-1', reason: 'Approval required' }

      useChatStore.getState().addApprovalRequiredMessage(approval)
      useChatStore.getState().addApprovalRequiredMessage(approval)

      const prompts = useChatStore.getState().messages.filter((m) => m.system_type === 'approval_required')
      expect(prompts).toHaveLength(1)
    })
  })
})
