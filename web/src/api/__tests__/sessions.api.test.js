import { sessionsApi } from '../sessions.api'

afterEach(() => {
  vi.restoreAllMocks()
})

function mockJsonResponse(body, status = 200) {
  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: () => Promise.resolve(JSON.stringify(body)),
  })
}

describe('sessionsApi', () => {
  it('creates an empty session through the sessions endpoint', async () => {
    mockJsonResponse({ session_id: 'session-1', title: 'New Session' }, 201)

    const result = await sessionsApi.create({ workspace_path: '/tmp/project' })

    expect(result.session_id).toBe('session-1')
    expect(globalThis.fetch).toHaveBeenCalledWith('/api/v1/sessions', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ workspace_path: '/tmp/project' }),
    }))
  })

  it('stops a running session through the sessions endpoint', async () => {
    mockJsonResponse({ status: 'stopped', session_id: 'session-1' })

    const result = await sessionsApi.stop('session-1')

    expect(result.status).toBe('stopped')
    expect(globalThis.fetch).toHaveBeenCalledWith('/api/v1/sessions/session-1/stop', expect.objectContaining({
      method: 'POST',
    }))
  })
})
