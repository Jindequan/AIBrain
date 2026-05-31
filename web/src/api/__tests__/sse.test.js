import { sseQuery } from '../sse'

afterEach(() => {
  vi.restoreAllMocks()
})

/**
 * Build a mock fetch response that yields SSE chunks through a ReadableStream reader.
 */
function mockFetchWithSse(chunks) {
  const encoder = new TextEncoder()
  const chunksCopy = [...chunks]

  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true,
    body: {
      getReader() {
        return {
          async read() {
            if (chunksCopy.length === 0) return { done: true, value: undefined }
            return { done: false, value: encoder.encode(chunksCopy.shift()) }
          },
        }
      },
    },
  })
}

describe('sseQuery', () => {
  it('calls onTextDelta for text_delta events', async () => {
    mockFetchWithSse([
      'event: message\ndata: {"type":"text_delta","data":{"text":"Hello "}}\n\n',
      'event: message\ndata: {"type":"text_delta","data":{"text":"world"}}\n\n',
    ])

    const onTextDelta = vi.fn()
    sseQuery({ query: 'hello' }, { onTextDelta })

    await vi.waitFor(() => {
      expect(onTextDelta).toHaveBeenCalledTimes(2)
    })
    expect(onTextDelta).toHaveBeenNthCalledWith(1, 'Hello ')
    expect(onTextDelta).toHaveBeenNthCalledWith(2, 'world')
  })

  it('calls onToolResult for tool_result events', async () => {
    mockFetchWithSse([
      'event: message\ndata: {"type":"tool_result","data":{"tool_use_id":"t1","output":"done"}}\n\n',
    ])

    const onToolResult = vi.fn()
    sseQuery({ query: 'run' }, { onToolResult })

    await vi.waitFor(() => {
      expect(onToolResult).toHaveBeenCalledWith({
        tool_use_id: 't1',
        output: 'done',
        status: 'success',
      })
    })
  })

  it('calls onToolResult for tool_start events with status running', async () => {
    mockFetchWithSse([
      'event: message\ndata: {"type":"tool_start","data":{"tool_use_id":"t1","tool_name":"bash","input":{"cmd":"ls"}}}\n\n',
    ])

    const onToolResult = vi.fn()
    sseQuery({ query: 'run' }, { onToolResult })

    await vi.waitFor(() => {
      expect(onToolResult).toHaveBeenCalledWith({
        tool_use_id: 't1',
        tool_name: 'bash',
        input: { cmd: 'ls' },
        status: 'running',
      })
    })
  })

  it('calls onComplete for complete events', async () => {
    mockFetchWithSse([
      'event: complete\ndata: {"response":"all done"}\n\n',
    ])

    const onComplete = vi.fn()
    sseQuery({ query: 'x' }, { onComplete })

    await vi.waitFor(() => {
      expect(onComplete).toHaveBeenCalledWith('all done')
    })
  })

  it('calls onError for error events', async () => {
    mockFetchWithSse([
      'event: error\ndata: {"error":"Server error"}\n\n',
    ])

    const onError = vi.fn()
    sseQuery({ query: 'x' }, { onError })

    await vi.waitFor(() => {
      expect(onError).toHaveBeenCalledWith('Server error')
    })
  })

  it('calls onError for query_failed events', async () => {
    mockFetchWithSse([
      'event: message\ndata: {"type":"query_failed","data":{"reason":"timeout"}}\n\n',
    ])

    const onError = vi.fn()
    sseQuery({ query: 'x' }, { onError })

    await vi.waitFor(() => {
      expect(onError).toHaveBeenCalledWith('timeout')
    })
  })

  it('gracefully handles malformed JSON without crashing', async () => {
    mockFetchWithSse([
      'event: message\ndata: not-valid-json\n\n',
      'event: message\ndata: {"type":"text_delta","data":{"text":"still works"}}\n\n',
    ])

    const onTextDelta = vi.fn()
    const onError = vi.fn()

    sseQuery({ query: 'safe' }, { onTextDelta, onError })

    await vi.waitFor(() => {
      // Bad JSON was silently skipped, valid event after it still fires
      expect(onTextDelta).toHaveBeenCalledWith('still works')
    })
    expect(onError).not.toHaveBeenCalled()
  })
})
