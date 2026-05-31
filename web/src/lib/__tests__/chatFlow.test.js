import { normalizeRouteSessionId, resolveSendSessionId } from '../chatFlow'

describe('chatFlow', () => {
  it('treats /chat and /sessions/new as no active route session', () => {
    expect(normalizeRouteSessionId(undefined)).toBeNull()
    expect(normalizeRouteSessionId(null)).toBeNull()
    expect(normalizeRouteSessionId('new')).toBeNull()
  })

  it('keeps real session ids', () => {
    expect(normalizeRouteSessionId('session-1')).toBe('session-1')
  })

  it('prefers the route session for sending', () => {
    expect(resolveSendSessionId('session-route', 'session-active')).toBe('session-route')
  })

  it('does not send to the pseudo new session id', () => {
    expect(resolveSendSessionId('new', null)).toBeNull()
    expect(resolveSendSessionId('new', 'new')).toBeNull()
  })

  it('does not reuse stale active session on the /chat new-session route', () => {
    expect(resolveSendSessionId(undefined, 'session-active')).toBeNull()
  })
})
